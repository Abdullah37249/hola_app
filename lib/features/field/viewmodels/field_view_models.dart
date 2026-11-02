import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';

/// Read helpers every sales-officer screen needs (salon names, owners, places).
mixin FieldLookups on RepoViewModel {
  SalonRepository get salons;
  AuthRepository get auth;

  Account? get me => auth.current;
  Salon? salon(String id) => salons.salon(id);
  String salonName(String id) => salons.salon(id)?.name ?? tr('Removed salon');
  Branch? mainBranch(String salonId) => salons.branches(salonId).firstOrNull;
  String place(String salonId) {
    final b = mainBranch(salonId);
    if (b == null) return '';
    return [b.area, b.city].where((x) => x.isNotEmpty).join(', ');
  }

  Account? owner(String salonId) {
    final s = salons.salon(salonId);
    return s == null ? null : auth.account(s.ownerId);
  }

  String personName(String id) => auth.account(id)?.name ?? tr('Former user');
}

// ─── Today ───────────────────────────────────────────────────────────────────

class FieldTodayViewModel extends RepoViewModel with FieldLookups {
  FieldTodayViewModel({required this.salons, required this.auth, required this.field, required this.trade}) : super(field);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final FieldRepository field;
  final TradeRepository trade;

  List<Visit> get todays => me == null ? const [] : field.visits(officerId: me!.id, day: today).where((v) => v.status != VisitStatus.cancelled).toList();
  int get visitsDone => todays.where((v) => v.status == VisitStatus.completed).length;
  Visit? get nextVisit => todays.where((v) => v.status != VisitStatus.completed).firstOrNull;

  List<TradeOrder> get _mineToday => trade.allOrders().where((o) => o.placedById == me?.id && sameDay(o.createdAt, today) && o.status != OrderStatus.cancelled).toList();
  int get bookedToday => _mineToday.fold(0, (t, o) => t + o.total);

  List<Salon> get toVerify => salons.allSalons().where((s) => s.status == SalonStatus.pending).toList();
  List<TradeOrder> get toApprove => trade.allOrders().where((o) => o.status == OrderStatus.placed || o.status == OrderStatus.underReview).toList();
  List<TradeOrder> get toDispatch => trade.allOrders().where((o) => o.status == OrderStatus.approved || o.status == OrderStatus.failed).toList();
  List<CashHandover> get handoversToConfirm => trade.handovers().where((h) => h.status == 'PENDING').toList();
  List<Salon> get orderable => salons.allSalons().where((s) => s.isActive).toList();
  bool get reportDone => me != null && field.reportFor(me!.id, today) != null;
}

// ─── Salons ──────────────────────────────────────────────────────────────────

class FieldSalonsViewModel extends RepoViewModel with FieldLookups {
  FieldSalonsViewModel({required this.salons, required this.auth}) : super(salons);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;

  static List<(String, String)> get filters => [('all', tr('All')), (SalonStatus.pending, tr('To verify')), (SalonStatus.active, tr('Verified')), (SalonStatus.changes, tr('Changes requested')), (SalonStatus.suspended, tr('Suspended'))];
  String filter = 'all';
  String query = '';

  void setFilter(String f) {
    filter = f;
    notify();
  }

  void setQuery(String q) {
    query = q;
    notify();
  }

  List<Salon> get all => salons.allSalons();
  int count(String f) => f == 'all' ? all.length : all.where((s) => s.status == f).length;

  List<Salon> get results {
    final q = query.trim().toLowerCase();
    return all.where((s) {
      if (filter != 'all' && s.status != filter) return false;
      if (q.isEmpty) return true;
      final hay = '${s.name} ${place(s.id)} ${owner(s.id)?.name ?? ''}'.toLowerCase();
      return q.split(RegExp(r'\s+')).every(hay.contains);
    }).toList();
  }

  int servicesCount(String salonId) => salons.services(salonId, activeOnly: true).length;
}

class SalonRecordViewModel extends RepoViewModel with FieldLookups {
  SalonRecordViewModel(this.id, {required this.salons, required this.auth, required this.field, required this.trade}) : super(salons);
  final String id;
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final FieldRepository field;
  final TradeRepository trade;

  Salon? get record => salons.salon(id);
  List<Branch> get branches => salons.branches(id);
  List<ServiceItem> get services => salons.services(id);
  List<StaffProfile> get team => salons.staff(id);
  List<Visit> get visits => field.visitsForSalon(id).where((v) => v.status != VisitStatus.cancelled).toList();
  List<TradeOrder> get orders => trade.ordersForSalon(id);
  SalonRating get rating => salons.rating(id);

  Future<void> approve() => salons.approveSalon(id);
  Future<void> requestChanges(String note) => salons.requestChanges(id, note);
  Future<void> suspend(String note) => salons.suspendSalon(id, note);
  Future<void> reactivate() => salons.reactivateSalon(id);
  Future<void> setTerms(int limit, int days) => trade.setCreditTerms(id, limit: limit, days: days);
}

// ─── Visits ──────────────────────────────────────────────────────────────────

class FieldVisitsViewModel extends RepoViewModel with FieldLookups {
  FieldVisitsViewModel({required this.salons, required this.auth, required this.field}) : super(field);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final FieldRepository field;

  DateTime day = today;

  /// Mon..Sun of the week being shown.
  DateTime weekStart = addDays(today, -(today.weekday - 1));
  List<DateTime> get week => [for (var i = 0; i < 7; i++) addDays(weekStart, i)];

  void pickDay(DateTime d) {
    day = dateOnly(d);
    weekStart = addDays(day, -(day.weekday - 1));
    notify();
  }

  void shiftWeek(int by) {
    weekStart = addDays(weekStart, 7 * by);
    day = sameDay(weekStart, addDays(today, -(today.weekday - 1))) ? today : weekStart;
    notify();
  }

  List<Visit> visitsOn(DateTime d) => me == null ? const [] : field.visits(officerId: me!.id, day: d).where((v) => v.status != VisitStatus.cancelled).toList();
  List<Visit> get selected => me == null ? const [] : field.visits(officerId: me!.id, day: day);
  List<Visit> get upcoming => me == null ? const [] : field.visits(officerId: me!.id).where((v) => v.status == VisitStatus.planned && v.plannedFor.isAfter(addDays(today, 1))).take(5).toList();
}

class VisitViewModel extends RepoViewModel with FieldLookups {
  VisitViewModel(this.id, {required this.salons, required this.auth, required this.field}) : super(field);
  final String id;
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final FieldRepository field;

  Visit? get visit => field.visit(id);

  // Report draft
  final outcomes = <String>{};
  String notes = '';
  String followUp = 'none'; // none | 1w | 2w | pick
  DateTime? pickedFollowUp;

  void toggleOutcome(String o) {
    outcomes.contains(o) ? outcomes.remove(o) : outcomes.add(o);
    notify();
  }

  void setFollowUp(String v, [DateTime? picked]) {
    followUp = v;
    if (picked != null) pickedFollowUp = picked;
    notify();
  }

  DateTime? get followUpAt {
    final v = visit;
    if (v == null) return null;
    DateTime at(DateTime d) => DateTime(d.year, d.month, d.day, v.plannedFor.hour, v.plannedFor.minute);
    return switch (followUp) {
      '1w' => at(addDays(today, 7)),
      '2w' => at(addDays(today, 14)),
      'pick' => pickedFollowUp == null ? null : at(pickedFollowUp!),
      _ => null,
    };
  }

  Future<void> checkIn() => field.checkIn(id);
  Future<void> cancel() => field.cancelVisit(id);
  Future<void> complete() => field.completeVisit(id, outcomes: outcomes.toList(), notes: notes, followUpAt: followUpAt);
}

// ─── Orders ──────────────────────────────────────────────────────────────────

class FieldOrdersViewModel extends RepoViewModel with FieldLookups {
  FieldOrdersViewModel({required this.salons, required this.auth, required this.trade}) : super(trade);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final TradeRepository trade;

  static List<(String, String)> get filters => [('approve', tr('Needs approval')), ('dispatch', tr('To dispatch')), ('delivery', tr('In delivery')), ('delivered', tr('Delivered')), ('all', tr('All'))];
  String filter = 'all';

  void setFilter(String f) {
    filter = f;
    notify();
  }

  bool _match(TradeOrder o, String f) => switch (f) {
        'approve' => o.status == OrderStatus.placed || o.status == OrderStatus.underReview,
        'dispatch' => o.status == OrderStatus.approved || o.status == OrderStatus.failed,
        'delivery' => o.status == OrderStatus.dispatched || o.status == OrderStatus.outForDelivery,
        'delivered' => o.status == OrderStatus.delivered || o.status == OrderStatus.confirmed,
        _ => true,
      };

  List<TradeOrder> get all => trade.allOrders();
  int count(String f) => all.where((o) => _match(o, f)).length;
  List<TradeOrder> get results => all.where((o) => _match(o, filter)).toList();

  int get openValue => all.where((o) => OrderStatus.open.contains(o.status)).fold(0, (t, o) => t + o.total);
  int get thisWeek => all.where((o) => o.createdAt.isAfter(addDays(today, -(today.weekday - 1))) && o.status != OrderStatus.cancelled).length;

  List<CashHandover> get pendingHandovers => trade.handovers().where((h) => h.status == 'PENDING').toList();
  List<CashHandover> get recentConfirmed => trade.handovers().where((h) => h.status == 'CONFIRMED').take(3).toList();
  Future<void> confirmHandover(String id) => trade.confirmHandover(id);
}

// ─── More: training, performance, daily report ───────────────────────────────

class TrainingsViewModel extends RepoViewModel with FieldLookups {
  TrainingsViewModel({required this.salons, required this.auth, required this.field}) : super(field);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final FieldRepository field;

  List<Training> get upcoming => field.trainings().where((t) => t.status == 'SCHEDULED').toList();
  List<Training> get past => field.trainings().where((t) => t.status != 'SCHEDULED').toList().reversed.toList();
}

class TrainingAdminViewModel extends RepoViewModel with FieldLookups {
  TrainingAdminViewModel(this.id, {required this.salons, required this.auth, required this.field}) : super(field);
  final String id;
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final FieldRepository field;

  Training? get training => field.training(id);
  bool get started => training != null && !training!.at.isAfter(now());

  /// Who attended (attendance draft before completing).
  final attended = <String>{};
  bool _seeded = false;
  void seedAttendance() {
    if (_seeded || training == null) return;
    _seeded = true;
    attended.addAll(training!.enrolled);
  }

  void toggle(String id) {
    attended.contains(id) ? attended.remove(id) : attended.add(id);
    notify();
  }

  String salonOf(String accountId) {
    final sid = auth.account(accountId)?.salonId;
    return sid == null ? '' : salonName(sid);
  }

  Future<void> cancel() => field.cancelTraining(id);
  Future<void> complete() => field.completeTraining(id, attended.toList());
}

class PerformanceViewModel extends RepoViewModel with FieldLookups {
  PerformanceViewModel({required this.salons, required this.auth, required this.field, required this.trade}) : super(field);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final FieldRepository field;
  final TradeRepository trade;

  String period = 'week'; // week | month
  void setPeriod(String p) {
    period = p;
    notify();
  }

  DateTime get from => period == 'week' ? addDays(today, -(today.weekday - 1)) : DateTime(today.year, today.month);
  bool _in(DateTime d) => !d.isBefore(from) && !d.isAfter(now());

  List<Visit> get _visits => me == null ? const [] : field.visits(officerId: me!.id).where((v) => _in(v.plannedFor) && v.status != VisitStatus.cancelled).toList();
  int get visitsPlanned => _visits.length;
  int get visitsDone => _visits.where((v) => v.status == VisitStatus.completed).length;
  double get completion => visitsPlanned == 0 ? 0 : visitsDone / visitsPlanned;

  List<TradeOrder> get _orders => trade.allOrders().where((o) => o.placedById == me?.id && _in(o.createdAt) && o.status != OrderStatus.cancelled).toList();
  int get ordersCount => _orders.length;
  int get ordersValue => _orders.fold(0, (t, o) => t + o.total);

  int get salonsVisited => _visits.where((v) => v.status == VisitStatus.completed).map((v) => v.salonId).toSet().length;
  int get activeSalons => salons.allSalons().where((s) => s.isActive).length;
  int get totalSalons => salons.allSalons().length;

  /// Outcome → how many completed visits recorded it.
  Map<String, int> get outcomeCounts {
    final m = <String, int>{};
    for (final v in _visits.where((v) => v.status == VisitStatus.completed)) {
      for (final o in v.outcomes) {
        m[o] = (m[o] ?? 0) + 1;
      }
    }
    return m;
  }
}

class DailyReportViewModel extends RepoViewModel with FieldLookups {
  DailyReportViewModel({required this.salons, required this.auth, required this.field, required this.trade}) : super(field);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final FieldRepository field;
  final TradeRepository trade;

  String notes = '';

  List<Visit> get todays => me == null ? const [] : field.visits(officerId: me!.id, day: today).where((v) => v.status != VisitStatus.cancelled).toList();
  int get visitsDone => todays.where((v) => v.status == VisitStatus.completed).length;
  List<TradeOrder> get ordersToday => trade.allOrders().where((o) => o.placedById == me?.id && sameDay(o.createdAt, today) && o.status != OrderStatus.cancelled).toList();
  int get ordersValue => ordersToday.fold(0, (t, o) => t + o.total);

  DailyReport? get submitted => me == null ? null : field.reportFor(me!.id, today);
  List<DailyReport> get past => me == null ? const [] : field.reports(me!.id).where((r) => !sameDay(r.day, today)).toList();

  Future<void> submit() => field.submitReport(notes: notes);
}
