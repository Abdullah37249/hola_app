import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/availability.dart';

/// Everything the salon-side screens read, for the signed-in owner or staff
/// member, plus the actions they can take. Page-scoped; stays live through
/// [RepoViewModel] so a customer's booking appears here straight away.
class SalonViewModel extends RepoViewModel {
  SalonViewModel({required this.salons, required this.bookings, required this.engage, required this.field, required this.auth, required this.chat}) : super(salons);

  factory SalonViewModel.of(BuildContext c) => SalonViewModel(
    salons: c.read<SalonRepository>(),
    bookings: c.read<BookingRepository>(),
    engage: c.read<EngagementRepository>(),
    field: c.read<FieldRepository>(),
    auth: c.read<AuthRepository>(),
    chat: c.read<ChatRepository>(),
  );

  final SalonRepository salons;
  final BookingRepository bookings;
  final EngagementRepository engage;
  final FieldRepository field;
  final AuthRepository auth;
  final ChatRepository chat;

  // ── who / where ──

  Account? get me => auth.current;
  bool get isOwner => me?.role == Role.salonOwner;
  Salon? get salon => me?.salonId == null ? null : salons.salon(me!.salonId!);

  /// Minutes before the start that check-in opens (HOLA's booking policy).
  int get checkInEarlyMin => salon?.checkInEarlyMin ?? 120;
  String get salonId => salon?.id ?? '';
  List<Branch> get branches => salons.branches(salonId);
  Branch? branch(String id) => salons.branch(id);
  List<StaffProfile> get team => salons.staff(salonId)
    ..sort(
      (a, b) => a.accountId == salon?.ownerId
          ? -1
          : b.accountId == salon?.ownerId
          ? 1
          : a.createdAt.compareTo(b.createdAt),
    );
  List<StaffProfile> get bookable => team.where((s) => s.bookable).toList();
  StaffProfile? profile(String accountId) => salons.staffProfile(accountId);
  Account? person(String id) => auth.account(id);
  String nameOf(String id) => person(id)?.name ?? tr('Former team member');
  String firstNameOf(String id) => person(id)?.firstName ?? tr('Former');

  // ── menu ──

  List<ServiceItem> get services => salons.services(salonId);
  List<ServiceItem> get activeServices => salons.services(salonId, activeOnly: true);
  ServiceItem? service(String id) => salons.service(id);

  // ── appointments ──

  List<Appointment> get all => bookings.forSalon(salonId);
  Appointment? appointment(String id) => bookings.appointment(id);

  List<Appointment> onDay(DateTime d, {String? staffId}) => all.where((a) => sameDay(a.startsAt, d) && (staffId == null || a.staffId == staffId)).toList();

  /// Requests waiting for an answer (not yet in the past).
  List<Appointment> requests({String? staffId}) => all.where((a) => a.status == ApptStatus.requested && a.endsAt.isAfter(now()) && (staffId == null || a.staffId == staffId)).toList();

  /// Today's appointments that still hold a chair and haven't ended.
  List<Appointment> upNext({String? staffId}) =>
      onDay(today, staffId: staffId).where((a) => {ApptStatus.confirmed, ApptStatus.checkedIn, ApptStatus.inService}.contains(a.status) && a.endsAt.isAfter(now())).toList();

  /// The client in the chair (or due now) for a professional.
  Appointment? current(String staffId) {
    final xs = upNext(staffId: staffId);
    return xs.where((a) => a.status == ApptStatus.inService || a.status == ApptStatus.checkedIn).firstOrNull ??
        xs.where((a) => !a.startsAt.isAfter(now().add(const Duration(minutes: 15)))).firstOrNull;
  }

  /// Revenue from today's appointments that are happening or done.
  int revenueOn(DateTime d, {String? staffId}) =>
      onDay(d, staffId: staffId).where((a) => a.status == ApptStatus.completed || ApptStatus.holding.contains(a.status) && a.status != ApptStatus.requested).fold(0, (t, a) => t + a.price);

  int countOn(DateTime d, {String? staffId}) => onDay(d, staffId: staffId).where((a) => a.status == ApptStatus.completed || ApptStatus.holding.contains(a.status)).length;

  bool canMarkNoShow(Appointment a) => bookings.canMarkNoShow(a);

  List<Slot> slots({required String branchId, required List<String> serviceIds, String? staffId, required DateTime day, String? rescheduling}) =>
      bookings.availability(branchId: branchId, serviceIds: serviceIds, staffId: staffId, day: day, rescheduling: rescheduling);

  /// The salon can message this booking's client (an app client, and chat
  /// reaches them: HOLA's chat is live, or the booking is on this phone).
  bool canMessage(Appointment a) => a.customerId != null && (chat.live || !a.hola);

  // ── clients ──

  /// Groups bookings by client: their HOLA account, else their phone number
  /// (a walk-in with the same number as an app client is the same person),
  /// else their name.
  Map<String, String> get _accountByPhone => {
    for (final a in all)
      if (a.customerId != null && _tel(a.customerPhone).isNotEmpty) _tel(a.customerPhone): a.customerId!,
  };
  static String _tel(String p) {
    final d = p.replaceAll(RegExp(r'\D'), '');
    return d.length >= 10 ? d.substring(d.length - 10) : d;
  }

  String _clientKey(Appointment a, Map<String, String> byPhone) {
    final t = _tel(a.customerPhone);
    return a.customerId ?? byPhone[t] ?? (t.isNotEmpty ? 'tel:$t' : 'name:${a.customerName.trim().toLowerCase()}');
  }

  String clientKeyOf(Appointment a) => _clientKey(a, _accountByPhone);

  /// Everyone who has booked or walked in, most recent visit first; [q]
  /// matches name or phone. HOLA's client list gives the full totals; the
  /// bookings on this phone add next visit, no-shows and usual services.
  List<ClientSummary> clients({String q = ''}) {
    final byPhone = _accountByPhone;
    final groups = <String, List<Appointment>>{};
    for (final a in all) {
      groups.putIfAbsent(_clientKey(a, byPhone), () => []).add(a);
    }
    final local = {for (final e in groups.entries) e.key: ClientSummary.of(e.key, e.value, now())};
    final merged = <String, ClientSummary>{};
    for (final r in bookings.clientList(salonId)) {
      final t = _tel(r.phone);
      final key = r.customerId ?? (t.isNotEmpty ? byPhone[t] ?? 'tel:$t' : 'name:${r.name.trim().toLowerCase()}');
      merged[key] = ClientSummary.server(key, r, merged[key] ?? local[key]);
    }
    for (final e in local.entries) {
      merged.putIfAbsent(e.key, () => e.value);
    }
    final query = q.trim().toLowerCase(), digits = q.replaceAll(RegExp(r'\D'), '');
    return merged.values.where((c) => query.isEmpty || c.name.toLowerCase().contains(query) || (digits.length >= 3 && c.phone.replaceAll(RegExp(r'\D'), '').contains(digits))).toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  }

  ClientSummary? client(String key) => clients().where((c) => c.key == key).firstOrNull;

  /// Fetches HOLA's client list.
  Future<void> loadClients() => bookings.syncClients(salonId);

  /// Fetches every visit of one client from HOLA (an app client's bookings,
  /// and any walk-ins under their phone number).
  Future<void> loadHistory(String key) async {
    final c = client(key);
    if (key.startsWith('tel:') || key.startsWith('name:')) {
      await bookings.syncClientHistory(salonId, phone: c?.phone ?? key.substring(4), name: c?.name ?? '');
      return;
    }
    await Future.wait([bookings.syncClientHistory(salonId, customerId: key), if (c != null && c.phone.isNotEmpty) bookings.syncClientHistory(salonId, phone: c.phone)]);
  }

  /// Every booking of one client at this salon, newest first.
  List<Appointment> history(String key) {
    final byPhone = _accountByPhone;
    return all.where((a) => _clientKey(a, byPhone) == key).toList()..sort((a, b) => b.startsAt.compareTo(a.startsAt));
  }

  Review? reviewOf(String appointmentId) => engage.reviewForAppointment(appointmentId);

  // ── inbox counts ──

  int get unreadMessages => chat.unreadTotal;

  /// Every review of the salon, including those HOLA hasn't published yet.
  List<Review> get reviews => engage.reviewsForSalon(salonId, withPending: true);
  SalonRating get rating => salons.rating(salonId);
  List<Complaint> get feedback => engage.complaintsForSalon(salonId);
  int get openFeedback => feedback.where((c) => c.status == 'OPEN').length;
  int get unrepliedReviews => reviews.where((r) => !r.pending && r.reply == null).length;
  int get waitingReviews => reviews.where((r) => r.pending).length;

  // ── team & leave ──

  List<LeaveRequest> get leave => salons.leave(salonId);
  List<LeaveRequest> get pendingLeave => leave.where((l) => l.status == 'PENDING').toList();
  List<LeaveRequest> leaveFor(String staffId) => salons.leaveFor(staffId);
  bool onLeave(String staffId, DateTime d) => leave.any((l) => l.staffId == staffId && l.status == 'APPROVED' && l.covers(d));

  // ── training ──

  /// Everyone at this salon who can be enrolled: the salon account first, then the team.
  List<String> get people => {if (me != null) me!.id, ...team.map((p) => p.accountId)}.toList();
  bool _ours(Training t) => t.enrolled.any(people.contains);

  /// People from this salon enrolled in [t].
  List<String> enrolledHere(Training t) => people.where(t.enrolled.contains).toList();
  List<String> attendedHere(Training t) => people.where(t.attended.contains).toList();

  bool isOpen(Training t) => t.status == 'SCHEDULED' && t.at.isAfter(now());
  List<Training> get trainings => field.trainings().where((t) => t.status != 'CANCELLED' || _ours(t)).toList();
  List<Training> get upcomingTrainings => trainings.where(isOpen).toList();
  List<Training> get pastTrainings => trainings.where((t) => !isOpen(t) && _ours(t)).toList().reversed.toList();
  Training? training(String id) => field.training(id);

  /// Sessions [personId] attended, newest first: each one is a certificate.
  List<Training> certificatesFor(String personId) => field.trainings().where((t) => t.status == 'COMPLETED' && t.attended.contains(personId)).toList().reversed.toList();

  /// Every certificate earned at this salon, newest first.
  List<(Training, String)> get certificates => [
    for (final t in field.trainings().reversed)
      if (t.status == 'COMPLETED')
        for (final id in attendedHere(t)) (t, id),
  ];
  int get minutesTrained => certificates.fold(0, (m, c) => m + c.$1.durationMin);

  // ── verification checklist ──

  bool get hasServices => activeServices.isNotEmpty;
  bool get hasTeamHours => bookable.any((s) => s.week.any((d) => d != null));
  bool get hasBranchHours => branches.any((b) => b.hours.any((h) => h != null));

  // ── actions (views wrap these in attempt()) ──

  Future<void> confirm(String id) => bookings.confirm(id);
  Future<void> decline(String id, String reason) => bookings.decline(id, reason);
  Future<void> cancel(String id, String reason) => bookings.cancel(id, reason);
  Future<void> checkIn(String id) => bookings.checkIn(id);
  Future<void> start(String id) => bookings.startService(id);
  Future<void> complete(String id) => bookings.complete(id);
  Future<void> noShow(String id) => bookings.noShow(id);
  Future<void> reschedule(String id, DateTime at, {String? staffId}) => bookings.reschedule(id, at, staffId: staffId);
  Future<void> resubmit() => salons.resubmitSalon(salonId);
  Future<void> decideLeave(String id, bool approve) => salons.decideLeave(id, approve: approve);
  Future<void> addLeave(String staffId, DateTime from, DateTime to, String reason) => salons.requestLeave(staffId: staffId, from: from, to: to, reason: reason);
  Future<void> withdrawLeave(String id) => salons.cancelLeave(id);
  Future<void> enrol(String id, {String? personId}) => field.enrol(id, personId: personId);
  Future<void> withdraw(String id, {String? personId}) => field.withdraw(id, personId: personId);

  /// Enrols or withdraws people so exactly [chosen] from this salon are going.
  Future<void> setEnrolled(Training t, Set<String> chosen) async {
    final going = enrolledHere(t).toSet();
    for (final id in going.difference(chosen)) {
      await field.withdraw(t.id, personId: id);
    }
    final add = chosen.difference(going);
    if (add.length > t.seatsLeft) throw DomainError(tr('Only {n} left in this session.', {'n': plural(t.seatsLeft, 'seat')}));
    for (final id in add) {
      await field.enrol(t.id, personId: id);
    }
  }

  Future<void> reply(String reviewId, String text) => engage.replyToReview(reviewId, text);
  bool get canDeleteReviews => isOwner && engage.reviewDelete;
  Future<void> deleteReview(String id) => engage.deleteReview(id);
  Future<void> resolve(String complaintId, String text) => engage.resolveComplaint(complaintId, text);
  // Offers & discounts
  List<ServiceOffer> get offers => salons.offers(salonId);
  int get runningOffers => offers.where((o) => o.liveAt(now())).length;
  Future<void> syncOffers() => salons.syncOffers(salonId: salonId);
  ({int used, int held}) offerStats(ServiceOffer o) => salons.offerStats(o);
  Future<void> setOfferActive(String id, bool on) => salons.setOfferActive(id, on);
  Future<void> deleteOffer(String id) => salons.deleteOffer(id);
  Future<ServiceOffer> saveOffer({
    String? id,
    required String serviceId,
    required String discountType,
    required int discountValue,
    required DateTime startDay,
    required DateTime lastDay,
    required bool active,
  }) => salons.saveOffer(id: id, salonId: salonId, serviceId: serviceId, discountType: discountType, discountValue: discountValue, startDay: startDay, lastDay: lastDay, active: active);

  Future<void> setServiceActive(String id, bool on) => salons.setServiceActive(id, on);
  Future<void> deleteService(String id) => salons.deleteService(id);
  Future<void> saveService({String? id, required String name, required String category, required String description, required int price, required int durationMin, required bool active}) =>
      salons.saveService(id: id, salonId: salonId, name: name, category: category, description: description, price: price, durationMin: durationMin, active: active);
  Future<Account> addStaff({required String name, required String phone, required String title}) => salons.addStaff(salonId, name: name, phone: phone, title: title);
  Future<void> updateStaff(String id, {required String title, required bool bookable, required List<Shift?> week, String? branchId}) =>
      salons.updateStaff(id, title: title, bookable: bookable, week: week, branchId: branchId);
  Future<void> removeStaff(String id) => salons.removeStaff(id);
  Future<void> updatePolicy({required bool autoConfirm, required int cancelWindowHours, required int noShowGraceMin}) =>
      salons.updatePolicy(salonId, autoConfirm: autoConfirm, cancelWindowHours: cancelWindowHours, noShowGraceMin: noShowGraceMin);
  Future<void> updateSalon({required String name, required String phone, required String about}) => salons.updateSalon(salonId, name: name, phone: phone, about: about);
  Future<void> setPhotos(List<String> photos) => salons.setSalonPhotos(salonId, photos);
  Future<Branch> addBranch({required String name, required String address, required String area, required String city}) =>
      salons.addBranch(salonId, name: name, address: address, area: area, city: city);
  Future<void> setBranchLocation(String id, GeoFix at) => salons.setBranchLocation(id, at);
  Future<void> updateBranch(String id, {required String name, required String address, required String area, required String city, required List<Shift?> hours}) =>
      salons.updateBranch(id, name: name, address: address, area: area, city: city, hours: hours);
  Future<void> deleteBranch(String id) => salons.deleteBranch(id);
  Future<Appointment> walkIn({required String branchId, required String name, required String phone, required List<String> serviceIds, required String staffId, required DateTime start}) =>
      bookings.walkIn(salonId: salonId, branchId: branchId, guestName: name, guestPhone: phone, serviceIds: serviceIds, staffId: staffId, start: start);
}

/// One client's record at this salon, built from their bookings.
class ClientSummary {
  final String key, name, phone;
  final bool hasAccount;
  final int bookings, completed, noShows, cancelled, spent;
  final DateTime? lastVisit, firstVisit;
  final Appointment? next;

  /// For sorting: the last visit, else the newest booking.
  final DateTime lastSeen;

  /// Services they had most, most frequent first.
  final List<String> favourites;

  const ClientSummary({
    required this.key,
    required this.name,
    required this.phone,
    required this.hasAccount,
    required this.bookings,
    required this.completed,
    required this.noShows,
    required this.cancelled,
    required this.spent,
    required this.lastVisit,
    required this.firstVisit,
    required this.next,
    required this.lastSeen,
    required this.favourites,
    this.fromServer = false,
  });

  /// Totals came from HOLA's client list.
  final bool fromServer;

  /// HOLA's totals for a client, with the extras only bookings can tell
  /// ([local], built from the bookings on this phone, or another HOLA entry
  /// for the same person, whose totals are added).
  factory ClientSummary.server(String key, ClientRecord r, ClientSummary? local) {
    final sameSource = local != null && local.fromServer;
    DateTime? pick(DateTime? a, DateTime? b, bool later) => a == null ? b : (b == null ? a : ((later ? a.isAfter(b) : a.isBefore(b)) ? a : b));
    final last = pick(r.lastVisitAt, local?.lastVisit, true);
    return ClientSummary(
      key: key,
      name: r.name.trim().isNotEmpty ? r.name.trim() : (local?.name ?? tr('Guest')),
      phone: r.phone.isNotEmpty ? r.phone : (local?.phone ?? ''),
      hasAccount: r.customerId != null || (local?.hasAccount ?? false),
      bookings: sameSource ? local.bookings + r.visits : (local == null ? r.visits : (r.visits > local.bookings ? r.visits : local.bookings)),
      completed: sameSource ? local.completed + r.completedVisits : (local == null ? r.completedVisits : (r.completedVisits > local.completed ? r.completedVisits : local.completed)),
      noShows: local?.noShows ?? 0,
      cancelled: local?.cancelled ?? 0,
      spent: sameSource ? local.spent + r.totalSpent : (local == null ? r.totalSpent : (r.totalSpent > local.spent ? r.totalSpent : local.spent)),
      lastVisit: last,
      firstVisit: pick(r.firstVisitAt, local?.firstVisit, false),
      next: local?.next,
      lastSeen: last ?? r.lastBookingAt ?? local?.lastSeen ?? DateTime(2000),
      favourites: local?.favourites ?? const [],
      fromServer: true,
    );
  }

  factory ClientSummary.of(String key, List<Appointment> xs, DateTime at) {
    final newest = [...xs]..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    final done = newest.where((a) => a.status == ApptStatus.completed).toList();
    final upcoming = newest.where((a) => ApptStatus.upcoming.contains(a.status) && a.startsAt.isAfter(at)).toList();
    final counts = <String, int>{};
    for (final a in done) {
      for (final n in a.serviceNames.where((n) => n.isNotEmpty)) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final named = newest.firstWhere((a) => a.customerName.trim().isNotEmpty, orElse: () => newest.first);
    return ClientSummary(
      key: key,
      name: named.customerName.trim().isEmpty ? tr('Guest') : named.customerName.trim(),
      phone: newest.map((a) => a.customerPhone).firstWhere((p) => p.isNotEmpty, orElse: () => ''),
      hasAccount: newest.any((a) => a.customerId != null),
      bookings: newest.length,
      completed: done.length,
      noShows: newest.where((a) => a.status == ApptStatus.noShow).length,
      cancelled: newest.where((a) => a.status == ApptStatus.cancelledByCustomer || a.status == ApptStatus.cancelledBySalon).length,
      spent: done.fold(0, (t, a) => t + a.price),
      lastVisit: done.firstOrNull?.startsAt,
      firstVisit: done.lastOrNull?.startsAt,
      next: upcoming.lastOrNull,
      lastSeen: done.firstOrNull?.startsAt ?? newest.first.startsAt,
      favourites: (counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!))).take(3).toList(),
    );
  }
}

/// Greeting for the time of day.
String greeting(DateTime t) => t.hour < 12
    ? tr('Good morning')
    : t.hour < 17
    ? tr('Good afternoon')
    : tr('Good evening');
