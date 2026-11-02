import '../../core/l10n/l10n.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/format.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/availability.dart';
import 'local_auth_repository.dart';

class LocalBookingRepository extends LocalRepository implements BookingRepository {
  LocalBookingRepository(super.db);

  Salon _salon(String id) => db.salons.where((s) => s.id == id).firstOrNull ?? (throw DomainError(tr('Salon not found.')));
  Appointment _appt(String id) => appointment(id) ?? (throw DomainError(tr('Appointment not found.')));
  List<ServiceItem> _services(List<String> ids) => [for (final id in ids) db.services.where((s) => s.id == id).firstOrNull ?? (throw DomainError(tr('A service is no longer offered.')))];
  String _when(Appointment a) => tr('{day} at {time}', _whenArgs(a));
  Map<String, String> _whenArgs(Appointment a) => {'day': dayLabel(a.startsAt, today), 'time': fmtTime(a.startsAt)};

  @override
  List<Slot> availability({required String branchId, required List<String> serviceIds, String? staffId, required DateTime day, String? rescheduling}) {
    final b = db.branches.where((x) => x.id == branchId).firstOrNull;
    if (b == null || serviceIds.isEmpty) return const [];
    final dur = _services(serviceIds).fold(0, (s, x) => s + x.durationMin);
    return availableSlots(
      day: day,
      branch: b,
      staff: db.staff.where((s) => s.salonId == b.salonId).toList(),
      appointments: db.appointments.where((a) => a.salonId == b.salonId).toList(),
      leave: db.leave.where((l) => l.salonId == b.salonId).toList(),
      durationMin: dur,
      now: now(),
      onlyStaffId: staffId,
      ignoreAppointmentId: rescheduling,
    );
  }

  @override
  Appointment? appointment(String id) => db.appointments.where((a) => a.id == id).firstOrNull;

  @override
  List<Appointment> forCustomer(String customerId) => db.appointments.where((a) => a.customerId == customerId).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  List<Appointment> forSalon(String salonId) => db.appointments.where((a) => a.salonId == salonId).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  List<Appointment> forStaff(String staffId) => db.appointments.where((a) => a.staffId == staffId).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  bool canCancelFree(Appointment a) => a.startsAt.difference(now()).inMinutes >= _salon(a.salonId).cancelWindowHours * 60;

  @override
  bool canMarkNoShow(Appointment a) => a.status == ApptStatus.confirmed && now().isAfter(a.startsAt.add(Duration(minutes: _salon(a.salonId).noShowGraceMin)));

  /// Picks the free professional with the fewest bookings that day (fair spread).
  String _assign(Slot slot, String salonId) {
    int load(String id) => db.appointments.where((a) => a.staffId == id && sameDay(a.startsAt, slot.start) && ApptStatus.holding.contains(a.status)).length;
    return ([...slot.staffIds]..sort((a, b) => load(a).compareTo(load(b)))).first;
  }

  Slot _slotOrThrow(String branchId, List<String> serviceIds, String? staffId, DateTime start, {String? rescheduling}) {
    final slots = availability(branchId: branchId, serviceIds: serviceIds, staffId: staffId, day: start, rescheduling: rescheduling);
    return slots.where((s) => s.start == start).firstOrNull ?? (throw DomainError(tr('Sorry, that time was just taken. Please pick another.')));
  }

  @override
  Future<Appointment> book({required String salonId, required String branchId, required List<String> serviceIds, String? staffId, required DateTime start, String notes = ''}) async {
    requireRole({Role.customer});
    final me = requireMe;
    final s = _salon(salonId);
    if (!s.isListed) throw DomainError(tr('This salon is not taking bookings right now.'));
    final svcs = _services(serviceIds);
    final slot = _slotOrThrow(branchId, serviceIds, staffId, start);
    final status = s.autoConfirm ? ApptStatus.confirmed : ApptStatus.requested;
    final a = Appointment(
      id: db.newId(),
      code: db.nextAppointmentCode(),
      salonId: salonId,
      branchId: branchId,
      customerId: me.id,
      customerName: me.name,
      customerPhone: me.phone,
      staffId: staffId ?? _assign(slot, salonId),
      serviceIds: serviceIds,
      serviceNames: [for (final x in svcs) x.name],
      startsAt: start,
      durationMin: svcs.fold(0, (t, x) => t + x.durationMin),
      price: svcs.fold(0, (t, x) => t + x.price),
      status: status,
      notes: notes.trim(),
      history: [StatusEvent(ApptStatus.requested, now(), me.id), if (s.autoConfirm) StatusEvent(ApptStatus.confirmed, now(), 'auto')],
      createdAt: now(),
    );
    db.appointments.add(a);
    final link = NotifLink('appointment', a.id);
    final what = a.serviceNames.join(', ');
    if (s.autoConfirm) {
      db.notify(me.id, 'Booking confirmed', '{salon} · {day} at {time}', args: {'salon': s.name, ..._whenArgs(a)}, icon: 'check', link: link);
      db.notifySalon(salonId, 'New booking', '{name} · {services} · {day} at {time}', args: {'name': me.name, 'services': what, ..._whenArgs(a)}, icon: 'cal', link: link, onlyStaffId: a.staffId);
    } else {
      db.notifySalon(salonId, 'New booking request', '{name} · {services} · {day} at {time}. Please confirm.', args: {'name': me.name, 'services': what, ..._whenArgs(a)}, icon: 'cal', link: link, onlyStaffId: a.staffId);
    }
    db.commit();
    return a;
  }

  @override
  Future<Appointment> walkIn({required String salonId, required String branchId, required String guestName, required String guestPhone, required List<String> serviceIds, required String staffId, required DateTime start}) async {
    requireRole({Role.salonOwner, Role.salonStaff});
    if (requireMe.salonId != salonId) throw DomainError(tr('Not your salon.'));
    if (guestName.trim().length < 2) throw DomainError(tr("Enter the client's name."));
    if (serviceIds.isEmpty) throw DomainError(tr('Pick at least one service.'));
    final svcs = _services(serviceIds);
    final dur = svcs.fold(0, (t, x) => t + x.durationMin);
    final end = start.add(Duration(minutes: dur));
    if (db.appointments.any((a) => a.staffId == staffId && ApptStatus.holding.contains(a.status) && a.startsAt.isBefore(end) && a.endsAt.isAfter(start))) {
      throw DomainError(tr('That professional is busy then.'));
    }
    final a = Appointment(
      id: db.newId(),
      code: db.nextAppointmentCode(),
      salonId: salonId,
      branchId: branchId,
      customerName: guestName.trim(),
      customerPhone: guestPhone.trim(),
      staffId: staffId,
      serviceIds: serviceIds,
      serviceNames: [for (final x in svcs) x.name],
      startsAt: start,
      durationMin: dur,
      price: svcs.fold(0, (t, x) => t + x.price),
      status: ApptStatus.confirmed,
      history: [StatusEvent(ApptStatus.confirmed, now(), requireMe.id, 'Walk-in')],
      createdAt: now(),
    );
    db.appointments.add(a);
    if (staffId != requireMe.id) db.notify(staffId, 'Walk-in added', '{name} · {services} · {day} at {time}', args: {'name': a.customerName, 'services': a.serviceNames.join(', '), ..._whenArgs(a)}, icon: 'cal', link: NotifLink('appointment', a.id));
    db.commit();
    return a;
  }

  // ── salon actions ──

  Appointment _forSalon(String id) {
    requireRole({Role.salonOwner, Role.salonStaff});
    final a = _appt(id);
    if (requireMe.salonId != a.salonId) throw DomainError(tr('Not your salon.'));
    return a;
  }

  void _move(Appointment a, String to, {String? note, required Set<String> from}) {
    if (!from.contains(a.status)) throw DomainError(tr('This appointment is already {status}.', {'status': statusLabel(a.status).toLowerCase()}));
    a.status = to;
    a.history.add(StatusEvent(to, now(), requireMe.id, note));
  }

  void _tellCustomer(Appointment a, String title, String body, String icon, [Map<String, String> args = const {}]) {
    if (a.customerId != null) db.notify(a.customerId!, title, body, args: args, icon: icon, link: NotifLink('appointment', a.id));
  }

  @override
  Future<void> confirm(String id) async {
    final a = _forSalon(id);
    _move(a, ApptStatus.confirmed, from: {ApptStatus.requested});
    _tellCustomer(a, 'Booking confirmed', '{salon} · {day} at {time}', 'check', {'salon': _salon(a.salonId).name, ..._whenArgs(a)});
    db.commit();
  }

  @override
  Future<void> decline(String id, String reason) async {
    final a = _forSalon(id);
    _move(a, ApptStatus.declined, note: reason.trim(), from: {ApptStatus.requested});
    _tellCustomer(a, "Salon couldn't take your booking", reason.trim().isEmpty ? '{salon} · {day} at {time}' : '{salon} · {day} at {time}. {reason}', 'x', {'salon': _salon(a.salonId).name, ..._whenArgs(a), 'reason': reason.trim()});
    db.commit();
  }

  @override
  Future<void> cancel(String id, String reason) async {
    final a = _appt(id);
    final me = requireMe;
    if (me.role == Role.customer) {
      if (a.customerId != me.id) throw DomainError(tr('Not your booking.'));
      a.lateCancel = a.status == ApptStatus.confirmed && !canCancelFree(a);
      _move(a, ApptStatus.cancelledByCustomer, note: reason.trim(), from: ApptStatus.upcoming);
      db.notifySalon(a.salonId, 'Booking cancelled', a.lateCancel ? '{name} cancelled {day} at {time} (late).' : '{name} cancelled {day} at {time}.', args: {'name': a.customerName, ..._whenArgs(a)}, icon: 'x', link: NotifLink('appointment', a.id), onlyStaffId: a.staffId);
    } else {
      _forSalon(id);
      _move(a, ApptStatus.cancelledBySalon, note: reason.trim(), from: ApptStatus.upcoming);
      _tellCustomer(a, 'Booking cancelled by salon', reason.trim().isEmpty ? '{salon} · {day} at {time}' : '{salon} · {day} at {time}. {reason}', 'x', {'salon': _salon(a.salonId).name, ..._whenArgs(a), 'reason': reason.trim()});
    }
    db.commit();
  }

  @override
  Future<void> reschedule(String id, DateTime start, {String? staffId}) async {
    final a = _appt(id);
    final me = requireMe;
    final isCustomer = me.role == Role.customer;
    if (isCustomer ? a.customerId != me.id : me.salonId != a.salonId) throw DomainError(tr('Not your booking.'));
    if (!ApptStatus.upcoming.contains(a.status)) throw DomainError(tr('Only upcoming bookings can be moved.'));
    final slot = _slotOrThrow(a.branchId, a.serviceIds, staffId, start, rescheduling: a.id);
    final before = _when(a);
    final beforeArgs = _whenArgs(a);
    a.startsAt = start;
    a.staffId = staffId ?? (slot.staffIds.contains(a.staffId) ? a.staffId : _assign(slot, a.salonId));
    final s = _salon(a.salonId);
    if (isCustomer && !s.autoConfirm) a.status = ApptStatus.requested;
    a.history.add(StatusEvent('RESCHEDULED', now(), me.id, 'From $before'));
    if (isCustomer) {
      db.notifySalon(a.salonId, 'Booking moved', '{name} moved {fromDay} at {fromTime} to {day} at {time}.', args: {'name': a.customerName, 'fromDay': beforeArgs['day']!, 'fromTime': beforeArgs['time']!, ..._whenArgs(a)}, icon: 'cal', link: NotifLink('appointment', a.id), onlyStaffId: a.staffId);
    } else {
      _tellCustomer(a, 'Your booking was moved', '{salon} moved it to {day} at {time}.', 'cal', {'salon': s.name, ..._whenArgs(a)});
    }
    db.commit();
  }

  @override
  Future<void> checkIn(String id) async {
    final a = _forSalon(id);
    if (a.startsAt.difference(now()).inHours >= 2) throw DomainError(tr('Check-in opens 2 hours before the appointment.'));
    _move(a, ApptStatus.checkedIn, from: {ApptStatus.confirmed});
    db.commit();
  }

  @override
  Future<void> startService(String id) async {
    final a = _forSalon(id);
    _move(a, ApptStatus.inService, from: {ApptStatus.checkedIn, ApptStatus.confirmed});
    db.commit();
  }

  @override
  Future<void> complete(String id) async {
    final a = _forSalon(id);
    _move(a, ApptStatus.completed, from: {ApptStatus.inService, ApptStatus.checkedIn});
    _tellCustomer(a, 'How was your visit?', 'Rate {salon} and help others choose.', 'star', {'salon': _salon(a.salonId).name});
    db.commit();
  }

  @override
  Future<void> noShow(String id) async {
    final a = _forSalon(id);
    if (!canMarkNoShow(a)) throw DomainError(tr('You can mark a no-show {n} minutes after the start time.', {'n': _salon(a.salonId).noShowGraceMin}));
    _move(a, ApptStatus.noShow, from: {ApptStatus.confirmed});
    _tellCustomer(a, 'Marked as no-show', '{salon} · {day} at {time}', 'alert', {'salon': _salon(a.salonId).name, ..._whenArgs(a)});
    db.commit();
  }
}
