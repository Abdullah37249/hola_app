import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/availability.dart';

/// Everything the salon-side screens read, for the signed-in owner or staff
/// member, plus the actions they can take. Page-scoped; stays live through
/// [RepoViewModel] so a customer's booking appears here straight away.
class SalonViewModel extends RepoViewModel {
  SalonViewModel({required this.salons, required this.bookings, required this.engage, required this.field, required this.auth}) : super(salons);

  factory SalonViewModel.of(BuildContext c) => SalonViewModel(
        salons: c.read<SalonRepository>(),
        bookings: c.read<BookingRepository>(),
        engage: c.read<EngagementRepository>(),
        field: c.read<FieldRepository>(),
        auth: c.read<AuthRepository>(),
      );

  final SalonRepository salons;
  final BookingRepository bookings;
  final EngagementRepository engage;
  final FieldRepository field;
  final AuthRepository auth;

  // ── who / where ──

  Account? get me => auth.current;
  bool get isOwner => me?.role == Role.salonOwner;
  Salon? get salon => me?.salonId == null ? null : salons.salon(me!.salonId!);
  String get salonId => salon?.id ?? '';
  List<Branch> get branches => salons.branches(salonId);
  Branch? branch(String id) => salons.branch(id);
  List<StaffProfile> get team => salons.staff(salonId)..sort((a, b) => a.accountId == salon?.ownerId ? -1 : b.accountId == salon?.ownerId ? 1 : a.createdAt.compareTo(b.createdAt));
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
  List<Appointment> requests({String? staffId}) =>
      all.where((a) => a.status == ApptStatus.requested && a.endsAt.isAfter(now()) && (staffId == null || a.staffId == staffId)).toList();

  /// Today's appointments that still hold a chair and haven't ended.
  List<Appointment> upNext({String? staffId}) =>
      onDay(today, staffId: staffId).where((a) => {ApptStatus.confirmed, ApptStatus.checkedIn, ApptStatus.inService}.contains(a.status) && a.endsAt.isAfter(now())).toList();

  /// The client in the chair (or due now) for a professional.
  Appointment? current(String staffId) {
    final xs = upNext(staffId: staffId);
    return xs.where((a) => a.status == ApptStatus.inService || a.status == ApptStatus.checkedIn).firstOrNull ?? xs.where((a) => !a.startsAt.isAfter(now().add(const Duration(minutes: 15)))).firstOrNull;
  }

  /// Revenue from today's appointments that are happening or done.
  int revenueOn(DateTime d, {String? staffId}) =>
      onDay(d, staffId: staffId).where((a) => a.status == ApptStatus.completed || ApptStatus.holding.contains(a.status) && a.status != ApptStatus.requested).fold(0, (t, a) => t + a.price);

  int countOn(DateTime d, {String? staffId}) => onDay(d, staffId: staffId).where((a) => a.status == ApptStatus.completed || ApptStatus.holding.contains(a.status)).length;

  bool canMarkNoShow(Appointment a) => bookings.canMarkNoShow(a);

  List<Slot> slots({required String branchId, required List<String> serviceIds, String? staffId, required DateTime day, String? rescheduling}) =>
      bookings.availability(branchId: branchId, serviceIds: serviceIds, staffId: staffId, day: day, rescheduling: rescheduling);

  /// A chat thread with this client, if they have written to the salon.
  ChatThread? threadWith(String? customerId) => customerId == null ? null : engage.threadsForSalon(salonId).where((t) => t.customerId == customerId).firstOrNull;

  // ── inbox counts ──

  int get unreadMessages => engage.threadsForSalon(salonId).fold(0, (t, x) => t + engage.unread(x.id, asSalon: true));
  List<Review> get reviews => engage.reviewsForSalon(salonId);
  SalonRating get rating => salons.rating(salonId);
  List<Complaint> get feedback => engage.complaintsForSalon(salonId);
  int get openFeedback => feedback.where((c) => c.status == 'OPEN').length;
  int get unrepliedReviews => reviews.where((r) => r.reply == null).length;

  // ── team & leave ──

  List<LeaveRequest> get leave => salons.leave(salonId);
  List<LeaveRequest> get pendingLeave => leave.where((l) => l.status == 'PENDING').toList();
  List<LeaveRequest> myLeave() => me == null ? const [] : salons.leaveFor(me!.id);
  bool onLeave(String staffId, DateTime d) => leave.any((l) => l.staffId == staffId && l.status == 'APPROVED' && l.covers(d));

  // ── training ──

  List<Training> get trainings => field.trainings().where((t) => t.status != 'CANCELLED' || t.enrolled.contains(me?.id)).toList();
  List<Training> get upcomingTrainings => trainings.where((t) => t.status == 'SCHEDULED' && t.at.isAfter(now())).toList();
  List<Training> get pastTrainings => trainings.where((t) => !(t.status == 'SCHEDULED' && t.at.isAfter(now())) && t.enrolled.contains(me?.id)).toList().reversed.toList();
  Training? training(String id) => field.training(id);

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
  Future<void> requestLeave(DateTime from, DateTime to, String reason) => salons.requestLeave(from: from, to: to, reason: reason);
  Future<void> withdrawLeave(String id) => salons.cancelLeave(id);
  Future<void> enrol(String id) => field.enrol(id);
  Future<void> withdraw(String id) => field.withdraw(id);
  Future<void> reply(String reviewId, String text) => engage.replyToReview(reviewId, text);
  Future<void> resolve(String complaintId, String text) => engage.resolveComplaint(complaintId, text);
  Future<void> setServiceActive(String id, bool on) => salons.setServiceActive(id, on);
  Future<void> deleteService(String id) => salons.deleteService(id);
  Future<void> saveService({String? id, required String name, required String category, required String description, required int price, required int durationMin, required bool active}) =>
      salons.saveService(id: id, salonId: salonId, name: name, category: category, description: description, price: price, durationMin: durationMin, active: active);
  Future<Account> addStaff({required String name, required String email, required String phone, required String password, required String title}) =>
      salons.addStaff(salonId, name: name, email: email, phone: phone, password: password, title: title);
  Future<void> updateStaff(String id, {required String title, required bool bookable, required List<Shift?> week}) => salons.updateStaff(id, title: title, bookable: bookable, week: week);
  Future<void> removeStaff(String id) => salons.removeStaff(id);
  Future<void> updatePolicy({required bool autoConfirm, required int cancelWindowHours, required int noShowGraceMin}) =>
      salons.updatePolicy(salonId, autoConfirm: autoConfirm, cancelWindowHours: cancelWindowHours, noShowGraceMin: noShowGraceMin);
  Future<void> updateSalon({required String name, required String phone, required String about}) => salons.updateSalon(salonId, name: name, phone: phone, about: about);
  Future<void> setPhotos(List<String> photos) => salons.setSalonPhotos(salonId, photos);
  Future<Branch> addBranch({required String name, required String address, required String area, required String city}) => salons.addBranch(salonId, name: name, address: address, area: area, city: city);
  Future<void> updateBranch(String id, {required String name, required String address, required String area, required String city, required List<Shift?> hours}) =>
      salons.updateBranch(id, name: name, address: address, area: area, city: city, hours: hours);
  Future<void> deleteBranch(String id) => salons.deleteBranch(id);
  Future<Appointment> walkIn({required String branchId, required String name, required String phone, required List<String> serviceIds, required String staffId, required DateTime start}) =>
      bookings.walkIn(salonId: salonId, branchId: branchId, guestName: name, guestPhone: phone, serviceIds: serviceIds, staffId: staffId, start: start);
}

/// Greeting for the time of day.
String greeting(DateTime t) => t.hour < 12 ? tr('Good morning') : t.hour < 17 ? tr('Good afternoon') : tr('Good evening');
