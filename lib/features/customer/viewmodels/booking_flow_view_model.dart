import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../domain/services/availability.dart';
import 'customer_lookups.dart';

/// Picks a day and a free time for a set of services, either for a new
/// booking or to move an existing one ([rescheduling]).
class SlotPickerViewModel extends RepoViewModel with CustomerLookups {
  SlotPickerViewModel(this.salons, this.auth, this.bookings, {required this.branchId, required this.serviceIds, this.staffId, this.rescheduling}) : super(bookings) {
    if (fromServer) {
      load();
    } else {
      _pickFirstOpenDay();
    }
  }

  /// HOLA salons: free times come from the server, two weeks at a time.
  bool get fromServer => salons.salon(salons.branch(branchId)?.salonId ?? '')?.hola ?? false;
  bool fetching = false;
  String? loadError;

  Future<void> load() async {
    fetching = true;
    loadError = null;
    notify();
    try {
      await bookings.loadAvailability(branchId: branchId, serviceIds: serviceIds, staffId: staffId, from: today, days: horizon);
      _pickFirstOpenDay();
    } on DomainError catch (e) {
      loadError = e.message;
    } finally {
      fetching = false;
      notify();
    }
  }

  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final BookingRepository bookings;
  final String branchId;
  final List<String> serviceIds;
  String? staffId; // null = any available professional
  final String? rescheduling;

  static const horizon = 14;
  DateTime day = today; // moved to the first open day once times load
  DateTime? time;

  List<DateTime> get days => [for (var i = 0; i < horizon; i++) addDays(today, i)];

  bool isClosed(DateTime d) => salons.branch(branchId)?.hoursOn(d) == null;
  List<Slot> slotsOn(DateTime d) => bookings.availability(branchId: branchId, serviceIds: serviceIds, staffId: staffId, day: d, rescheduling: rescheduling);
  bool isFull(DateTime d) => !isClosed(d) && slotsOn(d).isEmpty;

  List<Slot> get slots => slotsOn(day);

  /// Slots grouped into Morning / Afternoon / Evening.
  List<(String, List<Slot>)> get grouped {
    final s = slots;
    return [
      ('Morning', s.where((x) => x.start.hour < 12).toList()),
      ('Afternoon', s.where((x) => x.start.hour >= 12 && x.start.hour < 17).toList()),
      ('Evening', s.where((x) => x.start.hour >= 17).toList()),
    ].where((g) => g.$2.isNotEmpty).toList();
  }

  void _pickFirstOpenDay() {
    day = days.firstWhere((d) => slotsOn(d).isNotEmpty, orElse: () => today);
  }

  @override
  void refresh() {
    // Someone else may have taken the chosen time.
    if (time != null && !slots.any((s) => s.start == time)) time = null;
  }

  void pickDay(DateTime d) {
    day = d;
    if (time != null && !sameDay(time!, d)) time = null;
    notify();
  }

  void pickTime(DateTime t) {
    time = t;
    notify();
  }

  void setStaff(String? id) {
    staffId = id;
    time = null;
    if (fromServer) {
      load();
      return;
    }
    _pickFirstOpenDay();
    notify();
  }
}

/// Three-step booking: professional → time → review.
class BookingFlowViewModel extends SlotPickerViewModel {
  BookingFlowViewModel(super.salons, super.auth, super.bookings, {required this.salonId, required super.branchId, required super.serviceIds, super.staffId});
  final String salonId;

  static const steps = ['Professional', 'Date & time', 'Review'];
  int step = 1;
  String note = '';
  bool busy = false;

  Salon? get salonInfo => salons.salon(salonId);
  Branch? get branchInfo => salons.branch(branchId);
  List<ServiceItem> get services => [for (final id in serviceIds) ?salons.service(id)];
  int get total => services.fold(0, (t, x) => t + priceAfterOffer(x));
  int get minutes => services.fold(0, (t, x) => t + x.durationMin);
  List<(StaffProfile, String)> get pros => team(salonId, branchId: branchId);
  String? get staffName => staffId == null ? null : personName(staffId!);

  bool get canContinue => switch (step) {
    1 => true,
    2 => time != null,
    _ => !busy,
  };
  String get primaryLabel => switch (step) {
    3 => (salonInfo?.autoConfirm ?? false) ? tr('Book now') : tr('Send request'),
    _ => tr('Continue'),
  };

  void go(int d) {
    step = (step + d).clamp(1, 3);
    notify();
  }

  Future<Appointment> confirm() async {
    busy = true;
    notify();
    try {
      return await bookings.book(salonId: salonId, branchId: branchId, serviceIds: serviceIds, staffId: staffId, start: time!, notes: note);
    } on DomainError {
      // Slot was taken meanwhile: send the customer back to pick again.
      time = null;
      step = 2;
      if (fromServer) load();
      rethrow;
    } finally {
      busy = false;
      notify();
    }
  }
}
