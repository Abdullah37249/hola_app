import '../../core/l10n/l10n.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/format.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import 'local_auth_repository.dart';

class LocalFieldRepository extends LocalRepository implements FieldRepository {
  LocalFieldRepository(super.db);

  Visit _visit(String id) {
    final v = visit(id) ?? (throw DomainError(tr('Visit not found.')));
    if (v.officerId != requireMe.id) throw DomainError(tr('This visit belongs to another officer.'));
    return v;
  }

  // ── visits ──

  @override
  List<Visit> visits({String? officerId, DateTime? day}) =>
      db.visits.where((v) => (officerId == null || v.officerId == officerId) && (day == null || sameDay(v.plannedFor, day))).toList()..sort((a, b) => a.plannedFor.compareTo(b.plannedFor));

  @override
  List<Visit> visitsForSalon(String salonId) => db.visits.where((v) => v.salonId == salonId).toList()..sort((a, b) => b.plannedFor.compareTo(a.plannedFor));

  @override
  Visit? visit(String id) => db.visits.where((v) => v.id == id).firstOrNull;

  @override
  Future<Visit> planVisit({required String salonId, required DateTime at, required String purpose}) async {
    requireRole({Role.salesOfficer});
    if (!db.salons.any((s) => s.id == salonId)) throw DomainError(tr('Pick a salon.'));
    if (at.isBefore(today)) throw DomainError(tr("A visit can't be planned in the past."));
    if (purpose.trim().length < 3) throw DomainError(tr('Add the purpose of the visit.'));
    final v = Visit(id: db.newId(), officerId: requireMe.id, salonId: salonId, plannedFor: at, purpose: purpose.trim(), createdAt: now());
    db.visits.add(v);
    db.commit();
    return v;
  }

  @override
  Future<void> checkIn(String visitId) async {
    final v = _visit(visitId);
    if (v.status != VisitStatus.planned) throw DomainError(tr('Already checked in.'));
    if (!sameDay(v.plannedFor, now())) throw DomainError(tr('You can check in on the day of the visit.'));
    v
      ..status = VisitStatus.checkedIn
      ..checkInAt = now();
    db.commit();
  }

  @override
  Future<void> completeVisit(String visitId, {required List<String> outcomes, required String notes, DateTime? followUpAt}) async {
    final v = _visit(visitId);
    if (v.status != VisitStatus.checkedIn) throw DomainError(tr('Check in before completing the visit.'));
    if (outcomes.isEmpty) throw DomainError(tr('Pick at least one outcome.'));
    if (followUpAt != null && !followUpAt.isAfter(today)) throw DomainError(tr('The follow-up must be after today.'));
    v
      ..status = VisitStatus.completed
      ..completedAt = now()
      ..notes = notes.trim()
      ..followUpAt = followUpAt;
    v.outcomes
      ..clear()
      ..addAll(outcomes);
    if (followUpAt != null) {
      db.visits.add(Visit(id: db.newId(), officerId: v.officerId, salonId: v.salonId, plannedFor: followUpAt, purpose: 'Follow-up', createdAt: now()));
    }
    db.commit();
  }

  @override
  Future<void> cancelVisit(String visitId) async {
    final v = _visit(visitId);
    if (v.status != VisitStatus.planned) throw DomainError(tr('Only planned visits can be cancelled.'));
    v.status = VisitStatus.cancelled;
    db.commit();
  }

  // ── training ──

  @override
  List<Training> trainings() => [...db.trainings]..sort((a, b) => a.at.compareTo(b.at));

  @override
  Training? training(String id) => db.trainings.where((t) => t.id == id).firstOrNull;

  Training _t(String id) => training(id) ?? (throw DomainError(tr('Session not found.')));

  @override
  Future<Training> saveTraining({String? id, required String title, required String description, required String location, required DateTime at, required int durationMin, required int seats}) async {
    requireRole({Role.salesOfficer});
    if (title.trim().length < 3) throw DomainError(tr('Enter a title.'));
    if (location.trim().length < 3) throw DomainError(tr('Enter where it happens.'));
    if (!at.isAfter(now())) throw DomainError(tr('Pick a time in the future.'));
    if (seats < 1) throw DomainError(tr('Add at least one seat.'));
    if (durationMin < 15) throw DomainError(tr('Sessions are at least 15 minutes.'));
    final existing = id == null ? null : training(id);
    if (existing != null) {
      if (seats < existing.enrolled.length) throw DomainError(tr('{n} people are already enrolled.', {'n': existing.enrolled.length}));
      existing
        ..title = title.trim()
        ..description = description.trim()
        ..location = location.trim()
        ..at = at
        ..durationMin = durationMin
        ..seats = seats;
      for (final p in existing.enrolled) {
        db.notify(p, 'Training updated', '{title} · {date}, {time} · {location}', args: {'title': existing.title, 'date': dLabel(at), 'time': fmtTime(at), 'location': existing.location}, icon: 'grad', link: NotifLink('training', existing.id));
      }
      db.commit();
      return existing;
    }
    final t = Training(id: db.newId(), trainerId: requireMe.id, title: title.trim(), description: description.trim(), location: location.trim(), at: at, durationMin: durationMin, seats: seats, createdAt: now());
    db.trainings.add(t);
    for (final role in [Role.salonOwner, Role.salonStaff]) {
      db.notifyRole(role, 'New training: {title}', '{date}, {time} · {location} · {n} seats', args: {'title': t.title, 'date': dLabel(at), 'time': fmtTime(at), 'location': t.location, 'n': '$seats'}, icon: 'grad', link: NotifLink('training', t.id));
    }
    db.commit();
    return t;
  }

  @override
  Future<void> cancelTraining(String id) async {
    requireRole({Role.salesOfficer});
    final t = _t(id);
    if (t.status != 'SCHEDULED') throw DomainError(tr('This session is already closed.'));
    t.status = 'CANCELLED';
    for (final p in t.enrolled) {
      db.notify(p, 'Training cancelled', '{title} on {date}', args: {'title': t.title, 'date': dLabel(t.at)}, icon: 'x', link: NotifLink('training', t.id));
    }
    db.commit();
  }

  @override
  Future<void> enrol(String trainingId) async {
    requireRole({Role.salonOwner, Role.salonStaff});
    final t = _t(trainingId);
    final me = requireMe;
    if (t.status != 'SCHEDULED' || !t.at.isAfter(now())) throw DomainError(tr('Enrolment is closed.'));
    if (t.enrolled.contains(me.id)) return;
    if (t.seatsLeft <= 0) throw DomainError(tr('This session is full.'));
    t.enrolled.add(me.id);
    db.notify(t.trainerId, 'New enrolment', '{name} joined {title}.', args: {'name': me.name, 'title': t.title}, icon: 'grad', link: NotifLink('training', t.id));
    db.commit();
  }

  @override
  Future<void> withdraw(String trainingId) async {
    final t = _t(trainingId);
    if (t.enrolled.remove(requireMe.id)) db.commit();
  }

  @override
  Future<void> completeTraining(String id, List<String> attendedIds) async {
    requireRole({Role.salesOfficer});
    final t = _t(id);
    if (t.status != 'SCHEDULED') throw DomainError(tr('This session is already closed.'));
    if (t.at.isAfter(now())) throw DomainError(tr('Mark attendance after the session starts.'));
    t
      ..status = 'COMPLETED'
      ..attended.addAll(attendedIds.where(t.enrolled.contains));
    for (final p in t.attended) {
      db.notify(p, 'Training completed', 'You attended {title}. Well done!', args: {'title': t.title}, icon: 'grad', link: NotifLink('training', t.id));
    }
    db.commit();
  }

  // ── daily report ──

  @override
  List<DailyReport> reports(String officerId) => db.reports.where((r) => r.officerId == officerId).toList()..sort((a, b) => b.day.compareTo(a.day));

  @override
  DailyReport? reportFor(String officerId, DateTime day) => db.reports.where((r) => r.officerId == officerId && sameDay(r.day, day)).firstOrNull;

  @override
  Future<DailyReport> submitReport({required String notes}) async {
    requireRole({Role.salesOfficer});
    final me = requireMe;
    if (reportFor(me.id, today) != null) throw DomainError(tr("Today's report is already submitted."));
    final todays = visits(officerId: me.id, day: today).where((v) => v.status != VisitStatus.cancelled).toList();
    final orders = db.orders.where((o) => o.placedById == me.id && sameDay(o.createdAt, today) && o.status != OrderStatus.cancelled).toList();
    final r = DailyReport(
      id: db.newId(),
      officerId: me.id,
      day: today,
      visitsDone: todays.where((v) => v.status == VisitStatus.completed).length,
      visitsPlanned: todays.length,
      ordersCount: orders.length,
      ordersValue: orders.fold(0, (t, o) => t + o.total),
      notes: notes.trim(),
      submittedAt: now(),
    );
    db.reports.add(r);
    db.commit();
    return r;
  }
}
