import 'package:flutter/foundation.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/format.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import 'hola_mirror.dart' show mirrorPerson;
import 'local_auth_repository.dart';

class LocalFieldRepository extends LocalRepository implements FieldRepository {
  LocalFieldRepository(super.db, {this.api});

  /// HOLA server (training, contract 0.12.0); null keeps everything on the device.
  final HolaApi? api;

  // ── training on the HOLA server ──

  bool get _server => api != null && me != null && {Role.salonOwner, Role.salesOfficer, Role.trainer}.contains(me!.role);

  /// Salon team: staff member id (the app's person id) ↔ HOLA user id.
  final _userOfMember = <String, String>{};
  Future<void>? _trainingSync;

  @override
  Future<void> syncTrainings() => _trainingSync ??= _syncTrainings().whenComplete(() => _trainingSync = null);

  Future<void> _syncTrainings() async {
    if (!_server) return;
    final salonId = me!.role == Role.salonOwner ? me!.salonId : null;
    try {
      if (salonId != null) await _loadTeamIds(salonId);
      final all = <J>[];
      for (var page = 1, pages = 1; page <= pages && page <= 5; page++) {
        final res = await api!.get('/training/sessions', query: {'page': '$page', 'pageSize': '100', 'forSalonId': ?salonId});
        all.addAll((res is Map ? (res['data'] as List? ?? const []) : res as List).cast<J>());
        if (res is Map) pages = _n((res['meta'] as Map?)?['totalPages'], 1);
      }
      // Each session's enrolments (salon users only see their own salon's).
      final details = await Future.wait([for (final s in all) api!.get('/training/sessions/${s['id']}').then((d) => d as J).catchError((_) => s)]);
      final seen = <String>{};
      for (final d in details) {
        seen.add(_mirrorSession(d).id);
      }
      db.trainings.removeWhere((t) => t.onServer && !seen.contains(t.id));
      db.commit();
    } catch (e) {
      debugPrint('Training: sync failed: $e'); // offline: keep the last copy
    }
  }

  /// HOLA user ids for this salon's team (the app keys staff by member id).
  Future<void> _loadTeamIds(String salonId) async {
    final res = await api!.get('/salons/$salonId/staff');
    for (final m in (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<J>()) {
      if (m['id'] != null && m['userId'] != null) _userOfMember['${m['id']}'] = '${m['userId']}';
    }
  }

  /// The app's person id for a HOLA user: a team member's id, else the user id.
  String _personOf(String userId) => _userOfMember.entries.where((e) => e.value == userId).firstOrNull?.key ?? userId;
  String _userOf(String personId) => _userOfMember[personId] ?? personId;

  Training _mirrorSession(J j) {
    final id = '${j['id']}';
    final start = DateTime.parse('${j['startsAt']}').toLocal();
    final end = DateTime.tryParse('${j['endsAt'] ?? ''}')?.toLocal();
    final prog = (j['programme'] as Map?) ?? const {};
    final trainer = (j['trainer'] as Map?) ?? const {};
    final salon = j['salon'] as Map?;
    final venue = [j['venue'], j['city']].where((x) => x is String && x.isNotEmpty).join(', ');
    final enrolled = <String>[], attended = <String>[];
    final enrolmentOf = <String, String>{}, certificateOf = <String, String>{};
    for (final e in (j['enrolments'] as List? ?? const []).cast<Map>()) {
      final user = (e['user'] as Map?) ?? const {};
      final uid = '${user['id'] ?? ''}';
      if (uid.isEmpty) continue;
      final pid = _personOf(uid);
      // Names for people this phone doesn't know yet (officer view, the owner).
      if (db.accounts.every((a) => a.id != pid)) mirrorPerson(db, pid, '${user['fullName'] ?? ''}', salonId: (e['salon'] as Map?)?['id']?.toString());
      final st = '${e['status']}';
      if (st == 'CANCELLED') continue;
      enrolled.add(pid);
      enrolmentOf[pid] = '${e['id']}';
      if (st == 'ATTENDED') attended.add(pid);
      if (e['certificateNo'] != null) certificateOf[pid] = '${e['certificateNo']}';
    }
    final t = Training(
      id: id,
      trainerId: '${trainer['id'] ?? ''}',
      title: '${prog['title'] ?? ''}',
      description: '${j['notes'] ?? ''}',
      location: venue,
      at: start,
      // A class lasts minutes to hours; an end days away (a portal typo) falls back to the programme's length.
      durationMin: switch (end?.difference(start).inMinutes) {
        final m? when m > 0 && m <= 24 * 60 => m,
        _ => _n(prog['durationMin'], 120),
      },
      seats: _n(j['capacity']),
      enrolled: enrolled,
      attended: attended,
      status: '${j['status'] ?? 'SCHEDULED'}',
      createdAt: DateTime.tryParse('${j['createdAt'] ?? j['updatedAt'] ?? ''}')?.toLocal() ?? start,
      serverSeatsLeft: j['seatsLeft'] == null ? null : _n(j['seatsLeft']),
      enrolledCount: j['enrolledCount'] == null ? null : _n(j['enrolledCount']),
      trainerName: '${trainer['fullName'] ?? ''}',
      forSalon: salon == null ? '' : '${salon['name'] ?? ''}',
      allowed: {for (final a in (j['allowedActions'] as List? ?? const [])) '$a'.toLowerCase()},
      version: _n(j['version'], 1) < 1 ? 1 : _n(j['version'], 1),
      enrolmentOf: enrolmentOf,
      certificateOf: certificateOf,
    );
    final at = db.trainings.indexWhere((x) => x.id == id);
    at < 0 ? db.trainings.add(t) : db.trainings[at] = t;
    return t;
  }

  Future<void> _reload(String sessionId) async {
    final d = await api!.get('/training/sessions/$sessionId') as J;
    _mirrorSession(d);
    db.commit();
  }

  /// HOLA's refusal in the app's words (403: not a trainer).
  DomainError _trainingError(Object e) {
    if (e is ApiError && e.status == 403) return DomainError(tr('Only HOLA trainers can run sessions. Ask HOLA to give you the Trainer role.'));
    if (e is ApiError && e.code == 'SESSION_FULL') return DomainError(e.detail.isEmpty ? tr('This session is full.') : e.detail);
    return apiToDomain(e);
  }

  /// HOLA's programme with this title, created when it's new.
  Future<String> _programmeFor(String title, String description, int durationMin) async {
    final res = await api!.get('/training/programmes', query: {'all': 'true', 'pageSize': '100'});
    final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<J>();
    // Same title, any case; inactive programmes can't take new sessions.
    final same = list.where((p) => p['active'] != false && p['isActive'] != false && '${p['title']}'.trim().toLowerCase() == title.trim().toLowerCase()).firstOrNull;
    if (same != null) return '${same['id']}';
    final p =
        await api!.post(
              '/training/programmes',
              {'title': title.trim(), if (description.trim().isNotEmpty) 'description': description.trim(), 'durationMin': durationMin, 'certifies': true},
              headers: {'Idempotency-Key': db.newId() + db.newId()},
            )
            as J;
    return '${p['id']}';
  }

  /// The signed-in trainer, as HOLA lists them.
  Future<String> _trainerId() async {
    final res = await api!.get('/training/trainers');
    final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<J>();
    final mine = list.where((t) => '${t['id']}' == me!.id || '${t['userId']}' == me!.id).firstOrNull;
    if (mine == null) throw DomainError(tr('Only HOLA trainers can run sessions. Ask HOLA to give you the Trainer role.'));
    return '${mine['id']}';
  }

  Map<String, String> get _key => {'Idempotency-Key': db.newId() + db.newId()};

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
  Future<void> checkIn(String visitId, {GeoFix? where}) async {
    final v = _visit(visitId);
    if (v.status != VisitStatus.planned) throw DomainError(tr('Already checked in.'));
    if (!sameDay(v.plannedFor, now())) throw DomainError(tr('You can check in on the day of the visit.'));
    v
      ..status = VisitStatus.checkedIn
      ..checkInAt = now()
      ..checkInWhere = where;
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

  /// Who reads training news for each enrolled person: team members don't
  /// sign in, so their salon account gets it (once per salon).
  Set<String> _readers(Iterable<String> people) => {
    for (final id in people)
      switch (db.accounts.where((a) => a.id == id).firstOrNull) {
        final a? when a.role == Role.salonStaff => db.salons.where((s) => s.id == a.salonId).firstOrNull?.ownerId ?? id,
        _ => id,
      },
  };

  @override
  Future<Training> saveTraining({String? id, required String title, required String description, required String location, required DateTime at, required int durationMin, required int seats}) async {
    requireRole({Role.salesOfficer, Role.trainer});
    if (title.trim().length < 3) throw DomainError(tr('Enter a title.'));
    if (location.trim().length < 3) throw DomainError(tr('Enter where it happens.'));
    if (!at.isAfter(now())) throw DomainError(tr('Pick a time in the future.'));
    if (seats < 1) throw DomainError(tr('Add at least one seat.'));
    if (durationMin < 15) throw DomainError(tr('Sessions are at least 15 minutes.'));
    if (_server) {
      final cur = id == null ? null : training(id);
      final parts = location.split(',');
      final city = parts.length > 1 ? parts.last.trim() : null;
      final venue = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(',').trim() : location.trim();
      final times = {'startsAt': at.toUtc().toIso8601String(), 'endsAt': at.add(Duration(minutes: durationMin)).toUtc().toIso8601String()};
      try {
        final J res;
        if (cur != null && cur.onServer) {
          res = await api!.patch('/training/sessions/${cur.id}', {...times, 'venue': venue, 'city': ?city, 'capacity': seats, 'notes': description.trim(), 'version': cur.version}) as J;
        } else {
          final programmeId = await _programmeFor(title, description, durationMin);
          res =
              await api!.post('/training/sessions', {
                    'programmeId': programmeId,
                    'trainerId': await _trainerId(),
                    ...times,
                    'venue': venue,
                    'city': ?city,
                    'capacity': seats,
                    if (description.trim().isNotEmpty) 'notes': description.trim(),
                  }, headers: _key)
                  as J;
        }
        final t = _mirrorSession(res);
        db.commit();
        return t;
      } catch (e) {
        throw _trainingError(e);
      }
    }
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
      for (final p in _readers(existing.enrolled)) {
        db.notify(
          p,
          'Training updated',
          '{title} · {date}, {time} · {location}',
          args: {'title': existing.title, 'date': dLabel(at), 'time': fmtTime(at), 'location': existing.location},
          icon: 'grad',
          link: NotifLink('training', existing.id),
        );
      }
      db.commit();
      return existing;
    }
    final t = Training(
      id: db.newId(),
      trainerId: requireMe.id,
      title: title.trim(),
      description: description.trim(),
      location: location.trim(),
      at: at,
      durationMin: durationMin,
      seats: seats,
      createdAt: now(),
    );
    db.trainings.add(t);
    db.notifyRole(
      Role.salonOwner,
      'New training: {title}',
      '{date}, {time} · {location} · {n} seats',
      args: {'title': t.title, 'date': dLabel(at), 'time': fmtTime(at), 'location': t.location, 'n': '$seats'},
      icon: 'grad',
      link: NotifLink('training', t.id),
    );
    db.commit();
    return t;
  }

  @override
  Future<void> cancelTraining(String id) async {
    requireRole({Role.salesOfficer, Role.trainer});
    final t = _t(id);
    if (t.status != 'SCHEDULED') throw DomainError(tr('This session is already closed.'));
    if (t.onServer && api != null) {
      try {
        _mirrorSession(await api!.post('/training/sessions/$id/cancel', {'version': t.version}, headers: _key) as J);
        db.commit();
      } catch (e) {
        throw _trainingError(e);
      }
      return;
    }
    t.status = 'CANCELLED';
    for (final p in _readers(t.enrolled)) {
      db.notify(p, 'Training cancelled', '{title} on {date}', args: {'title': t.title, 'date': dLabel(t.at)}, icon: 'x', link: NotifLink('training', t.id));
    }
    db.commit();
  }

  /// The signed-in salon account, or a member of its team.
  Account _person(String? personId) {
    requireRole({Role.salonOwner});
    final me = requireMe;
    if (personId == null || personId == me.id) return me;
    final p = db.accounts.where((a) => a.id == personId).firstOrNull;
    if (p == null || p.salonId == null || p.salonId != me.salonId) throw DomainError(tr('Team member not found.'));
    return p;
  }

  @override
  Future<void> enrol(String trainingId, {String? personId}) async {
    final p = _person(personId);
    final t = _t(trainingId);
    if (t.status != 'SCHEDULED' || !t.at.isAfter(now())) throw DomainError(tr('Enrolment is closed.'));
    if (t.enrolled.contains(p.id)) return;
    if (t.seatsLeft <= 0) throw DomainError(tr('This session is full.'));
    if (t.onServer && api != null) {
      try {
        await api!.post('/training/sessions/${t.id}/enrol', {
          'salonId': requireMe.salonId,
          'userIds': [_userOf(p.id)],
        }, headers: _key);
        await _reload(t.id);
      } catch (e) {
        throw _trainingError(e);
      }
      return;
    }
    t.enrolled.add(p.id);
    final salon = db.salons.where((s) => s.id == p.salonId).firstOrNull;
    db.notify(
      t.trainerId,
      'New enrolment',
      '{name} joined {title}.',
      args: {'name': salon == null ? p.name : '${p.name} · ${salon.name}', 'title': t.title},
      icon: 'grad',
      link: NotifLink('training', t.id),
    );
    db.commit();
  }

  @override
  Future<void> withdraw(String trainingId, {String? personId}) async {
    final p = _person(personId);
    final t = _t(trainingId);
    if (t.status != 'SCHEDULED' || !t.at.isAfter(now())) throw DomainError(tr('Enrolment is closed.'));
    if (t.onServer && api != null) {
      final eid = t.enrolmentOf[p.id];
      if (eid == null) return;
      try {
        await api!.post('/training/enrolments/$eid/cancel', const {}, headers: _key);
        await _reload(t.id);
      } catch (e) {
        throw _trainingError(e);
      }
      return;
    }
    if (t.enrolled.remove(p.id)) db.commit();
  }

  @override
  Future<void> completeTraining(String id, List<String> attendedIds) async {
    requireRole({Role.salesOfficer, Role.trainer});
    final t = _t(id);
    if (t.status != 'SCHEDULED') throw DomainError(tr('This session is already closed.'));
    if (t.at.isAfter(now())) throw DomainError(tr('Mark attendance after the session starts.'));
    if (t.onServer && api != null) {
      try {
        final items = [
          for (final MapEntry(key: pid, value: eid) in t.enrolmentOf.entries) {'enrolmentId': eid, 'attended': attendedIds.contains(pid)},
        ];
        if (items.isNotEmpty) await api!.post('/training/sessions/$id/attendance', {'items': items}, headers: _key);
        final fresh = await api!.get('/training/sessions/$id') as J;
        _mirrorSession(await api!.post('/training/sessions/$id/complete', {'version': _n(fresh['version'], t.version)}, headers: _key) as J);
        await _reload(id);
      } catch (e) {
        throw _trainingError(e);
      }
      return;
    }
    t
      ..status = 'COMPLETED'
      ..attended.addAll(attendedIds.where(t.enrolled.contains));
    final owners = <String, List<String>>{}; // salon account → team members who attended
    for (final id in t.attended) {
      final a = db.accounts.where((x) => x.id == id).firstOrNull;
      if (a?.role == Role.salonStaff) {
        owners.putIfAbsent(_readers([id]).first, () => []).add(a!.firstName);
      } else {
        db.notify(id, 'Training completed', 'You attended {title}. Your certificate is ready.', args: {'title': t.title}, icon: 'grad', link: NotifLink('training', t.id));
      }
    }
    for (final MapEntry(key: owner, value: names) in owners.entries) {
      db.notify(owner, 'Training completed', '{names} attended {title}. Certificates are ready.', args: {'names': names.join(', '), 'title': t.title}, icon: 'grad', link: NotifLink('training', t.id));
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

/// A number from HOLA JSON (number or text), or [d].
int _n(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? d;
