import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import 'customer_lookups.dart';

/// Bookings tab: upcoming and past appointments of the signed-in customer.
class BookingsViewModel extends RepoViewModel with CustomerLookups {
  BookingsViewModel(this.salons, this.auth, this.bookings) : super(bookings);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final BookingRepository bookings;

  String segment = 'up';

  List<Appointment> get _mine => me == null ? const [] : bookings.forCustomer(me!.id);

  List<Appointment> get upcoming => _mine.where((a) => ApptStatus.holding.contains(a.status) && a.endsAt.isAfter(now())).toList();

  List<Appointment> get past => _mine.where((a) => !upcoming.contains(a)).toList().reversed.toList();

  void setSegment(String s) {
    segment = s;
    notify();
  }
}

/// One booking: actions the customer can take and its review/complaint.
class BookingDetailViewModel extends RepoViewModel with CustomerLookups {
  BookingDetailViewModel(this.salons, this.auth, this.bookings, this.engage, this.id) : super(bookings);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final BookingRepository bookings;
  final EngagementRepository engage;
  final String id;

  Appointment? get a => bookings.appointment(id);
  Salon? get s => a == null ? null : salons.salon(a!.salonId);
  Branch? get b => a == null ? null : salons.branch(a!.branchId);
  Review? get review => engage.reviewForAppointment(id);
  List<Complaint> get complaints => me == null ? const [] : engage.complaintsForCustomer(me!.id).where((c) => c.appointmentId == id).toList();

  bool get isUpcoming => a != null && ApptStatus.upcoming.contains(a!.status) && a!.startsAt.isAfter(now());
  bool get canReview => a?.status == ApptStatus.completed && review == null;
  bool get freeCancel => a != null && (a!.status == ApptStatus.requested || bookings.canCancelFree(a!));

  Future<void> cancel(String reason) => bookings.cancel(id, reason);
  Future<void> reschedule(DateTime start, String? staffId) => bookings.reschedule(id, start, staffId: staffId);
  Future<void> addReview(int stars, String text) => engage.addReview(appointmentId: id, stars: stars, text: text);
}

/// Feedback & complaints the customer has raised.
class FeedbackViewModel extends RepoViewModel with CustomerLookups {
  FeedbackViewModel(this.salons, this.auth, this.bookings, this.engage) : super(engage);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final BookingRepository bookings;
  final EngagementRepository engage;

  List<Complaint> get items => me == null ? const [] : engage.complaintsForCustomer(me!.id);

  /// Salons the customer has booked (most recent first), for picking one.
  List<Salon> get bookedSalons {
    if (me == null) return const [];
    final ids = <String>[];
    for (final a in bookings.forCustomer(me!.id).reversed) {
      if (!ids.contains(a.salonId)) ids.add(a.salonId);
    }
    return [for (final i in ids) ?salons.salon(i)];
  }

  Future<void> raise({required String salonId, String? appointmentId, required String topic, required String text}) =>
      engage.raiseComplaint(salonId: salonId, appointmentId: appointmentId, topic: topic, text: text);
}

/// Topics a customer can raise feedback about. Fixed vocabulary.
const feedbackTopics = ['Service quality', 'Waiting time', 'Staff behaviour', 'Price or billing', 'Hygiene', 'Booking problem', 'Compliment', 'Other'];

/// Products tab: HOLA catalogue (retail prices) and salons to ask about it.
class ShopViewModel extends RepoViewModel with CustomerLookups {
  ShopViewModel(this.salons, this.auth, this.bookings, this.trade) : super(trade);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final BookingRepository bookings;
  final TradeRepository trade;

  String? category;

  List<Product> get _retail => trade.products().where((p) => p.variants.any((v) => v.retailPrice > 0)).toList();
  List<String> get categories => [for (final c in productCategories) if (_retail.any((p) => p.category == c)) c];
  List<Product> get items => _retail.where((p) => category == null || p.category == category).toList();

  int retailFrom(Product p) => p.variants.where((v) => v.retailPrice > 0).map((v) => v.retailPrice).reduce((a, b) => a < b ? a : b);

  List<Salon> get bookedSalons {
    if (me == null) return const [];
    final ids = <String>[];
    for (final a in bookings.forCustomer(me!.id).reversed) {
      if (!ids.contains(a.salonId)) ids.add(a.salonId);
    }
    return [for (final i in ids) ?salons.salon(i)];
  }

  void setCategory(String? c) {
    category = c;
    notify();
  }
}
