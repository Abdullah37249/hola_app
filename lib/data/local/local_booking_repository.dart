import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/l10n/l10n.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/format.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/availability.dart';
import 'local_auth_repository.dart';
import 'hola_mirror.dart';
import 'local_database.dart';
import 'hola_salon_sync.dart';
import 'offer_rules.dart';
import '../../core/network/api.dart';
import '../../domain/entities/json.dart' show asInt;

class LocalBookingRepository extends LocalRepository implements BookingRepository {
  LocalBookingRepository(super.db, {this.api});

  /// When set, bookings at HOLA salons go through the HOLA server.
  final HolaApi? api;

  bool _isHola(String salonId) => api != null && (db.salons.where((s) => s.id == salonId).firstOrNull?.hola ?? false);

  // ── HOLA server ──

  /// Free times loaded from the server, by branch|services|staff|date.
  final _slots = <String, List<Slot>>{};
  String _key(String branchId, List<String> serviceIds, String? staffId, DateTime day) => '$branchId|${serviceIds.join(',')}|${staffId ?? ''}|${dateOnly(day).toIso8601String()}';
  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<void> loadAvailability({required String branchId, required List<String> serviceIds, String? staffId, required DateTime from, int days = 14}) async {
    if (api == null || serviceIds.isEmpty) return;
    try {
      final res =
          await api!.get(
                '/branches/$branchId/availability',
                auth: false,
                query: {'serviceIds': serviceIds.join(','), if (staffId != null) 'staffId': staffId, 'from': _ymd(from), 'days': '${days.clamp(1, 14)}'},
              )
              as J;
      for (var i = 0; i < days; i++) {
        _slots[_key(branchId, serviceIds, staffId, addDays(from, i))] = const [];
      }
      for (final d in (res['days'] as List? ?? const []).cast<J>()) {
        final day = DateTime.parse(d['date'] as String);
        _slots[_key(branchId, serviceIds, staffId, day)] = [
          for (final x in (d['slots'] as List? ?? const []).cast<J>()) Slot(DateTime.parse(x['start'] as String).toLocal(), [for (final id in (x['staffIds'] as List? ?? const [])) '$id']),
        ];
      }
      db.commit(); // let the time picker redraw
    } on ApiError catch (e) {
      if (e.code == 'INVALID_REFERENCE' && staffId != null) {
        throw DomainError(tr('This stylist can’t be booked online right now. Go back and pick another stylist or “Any professional”.'));
      }
      throw apiToDomain(e);
    }
  }

  /// Runs a server action and copies the booking it returns.
  Future<Appointment> _remote(Future<dynamic> Function() call, {Map<String, String> codes = const {}}) async {
    try {
      final res = await call();
      final a = mirrorAppointment(db, res as J, actor: me?.id);
      db.commit();
      return a;
    } on ApiError catch (e) {
      final msg = codes[e.code];
      if (msg != null) throw DomainError(msg);
      throw apiToDomain(e);
    }
  }

  static Map<String, String> get _slotCodes => {
    'APPOINTMENT_SLOT_TAKEN': tr('Someone just took that time. Please pick another.'),
    'APPOINTMENT_SLOT_UNAVAILABLE': tr('That time can’t be booked any more. Please pick another.'),
    'VERSION_CONFLICT': tr('This booking changed meanwhile. Please try again.'),
    'APPOINTMENT_TOO_EARLY': tr('It’s too early for that. Try again a little later.'),
  };

  Future<void>? _syncing;
  final _repaired = <String>{};

  /// People whose first sync has run (the first one fills the list quietly).
  final _synced = <String>{};
  final _seen = <String, String?>{};

  /// The status this phone last knew for a booking in [j], read before it's replaced.
  String? _before(J j) => _seen[j['id']] ?? appointment(j['id'] as String)?.status;

  /// Tells the person when the other side changed a booking: the customer
  /// when the salon confirms, declines, cancels or moves it; the salon when a
  /// new request or a cancellation arrives.
  void _announce(Account m, Appointment a, String? before) {
    _seen[a.id] = a.status;
    if (!_synced.contains(m.id) || before == a.status) return;
    final args = {'salon': _salon(a.salonId).name, 'name': a.customerName, ..._whenArgs(a)};
    final link = NotifLink('appointment', a.id);
    // HOLA's push about this change already landed.
    if (db.recentAbout(m.id, link) != null) return;
    if (m.role == Role.customer) {
      switch (a.status) {
        case ApptStatus.confirmed when before == ApptStatus.requested:
          db.notify(m.id, 'Booking confirmed', '{salon} · {day} at {time}', args: args, icon: 'check', link: link);
        case ApptStatus.cancelledBySalon || ApptStatus.declined:
          db.notify(m.id, "Salon couldn't take your booking", '{salon} · {day} at {time}', args: args, icon: 'x', link: link);
        case ApptStatus.completed:
          db.notify(m.id, 'Thanks for visiting {salon}', 'How was it? Rate your visit.', args: args, icon: 'star', link: link);
      }
    } else {
      if (before == null && a.status == ApptStatus.requested) {
        db.notify(m.id, 'New booking request', '{name} · {day} at {time}', args: args, icon: 'cal', link: link);
      } else if (before == null && a.status == ApptStatus.confirmed) {
        db.notify(m.id, 'New booking', '{name} · {day} at {time}', args: args, icon: 'cal', link: link);
      } else if (a.status == ApptStatus.cancelledByCustomer) {
        db.notify(m.id, 'Booking cancelled', '{name} cancelled {day} at {time}.', args: args, icon: 'x', link: link);
      }
    }
  }

  @override
  Future<void> syncBookingHistory(String id) async {
    final a = appointment(id);
    if (a == null || !a.hola || api == null) return;
    try {
      final res = await api!.get('/appointments/$id/history');
      final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<Map>();
      if (list.isEmpty) return;
      final events = [
        for (final e in list)
          StatusEvent('${e['toStatus']}', DateTime.tryParse('${e['at']}')?.toLocal() ?? a.createdAt, '${(e['actor'] as Map?)?['id'] ?? ''}', switch ('${e['note'] ?? ''}'.trim()) {
            '' => null,
            final n => n,
          }),
      ];
      for (final e in list) {
        final actor = e['actor'] as Map?;
        // Salon people get a name to show; customers are named on the booking.
        if (actor?['kind'] == 'SALON' && actor?['id'] != null) mirrorPerson(db, '${actor!['id']}', '${actor['fullName'] ?? ''}', salonId: a.salonId);
      }
      a.history
        ..clear()
        ..addAll(events);
      db.commit();
    } catch (e) {
      debugPrint('Booking history: sync failed: $e'); // keep what the phone has
    }
  }

  @override
  Future<void> sync() => api == null ? Future.value() : (_syncing ??= _sync().whenComplete(() => _syncing = null));

  Future<void> _sync() async {
    final m = me;
    if (m == null) return;
    try {
      if (m.role == Role.customer) {
        for (var page = 1, pages = 1; page <= pages; page++) {
          final res = await api!.get('/me/appointments', query: {'when': 'all', 'page': '$page', 'pageSize': '100'}) as J;
          pages = asInt((res['meta'] as Map?)?['totalPages'], 1);
          for (final j in (res['data'] as List).cast<J>()) {
            _announce(m, mirrorAppointment(db, j), _before(j));
          }
        }
      } else if (m.role == Role.salonOwner && m.salonId != null && _isHola(m.salonId!)) {
        // Once per app run: make sure the owner is a bookable stylist with hours
        // (fixes salons set up before the app saved working hours correctly).
        if (_repaired.add(m.salonId!)) {
          try {
            await HolaSalonSync(db, api!).ensureOwnerBookable(m.salonId!, m.id);
          } catch (_) {}
        }
        // The salon calendar: a month back to two months ahead, page by page.
        final range = {'from': isoWithOffset(addDays(today, -30)), 'to': isoWithOffset(addDays(today, 60))};
        for (var page = 1, pages = 1; page <= pages; page++) {
          final res = await api!.get('/salons/${m.salonId}/appointments', query: {...range, 'page': '$page', 'pageSize': '100'}) as J;
          pages = asInt((res['meta'] as Map?)?['totalPages'], 1);
          for (final j in (res['data'] as List).cast<J>()) {
            _announce(m, mirrorAppointment(db, j), _before(j));
          }
        }
      }
      _synced.add(m.id);
      db.commit();
    } catch (_) {
      // Offline: keep what we have; the offline banner explains.
    }
  }

  // ── client history (contract 0.16.0) ──

  final _clients = <String, List<ClientRecord>>{};

  @override
  List<ClientRecord> clientList(String salonId) => _clients[salonId] ?? const [];

  @override
  Future<void> syncClients(String salonId) async {
    if (!_isHola(salonId)) return;
    final out = <ClientRecord>[];
    for (var page = 1, pages = 1; page <= pages && page <= 20; page++) {
      final res = await api!.get('/salons/$salonId/clients', query: {'page': '$page', 'pageSize': '100'}) as J;
      pages = asInt((res['meta'] as Map?)?['totalPages'], 1);
      for (final j in (res['data'] as List).cast<Map>()) {
        DateTime? t(String k) => DateTime.tryParse('${j[k] ?? ''}')?.toLocal();
        // Contract 0.18.0: `visits` counts completed visits and `bookings` all of them.
        final v18 = j.containsKey('bookings');
        out.add(
          ClientRecord(
            customerId: j['customerId'] as String?,
            name: '${j['name'] ?? ''}',
            phone: '${j['phone'] ?? ''}',
            visits: asInt(v18 ? j['bookings'] : j['visits'], 0),
            completedVisits: asInt(v18 ? j['visits'] : j['completedVisits'], 0),
            totalSpent: (double.tryParse('${j['totalSpent'] ?? 0}') ?? 0).round(),
            firstVisitAt: t('firstVisitAt'),
            lastVisitAt: t('lastVisitAt'),
            lastBookingAt: t('lastBookingAt'),
          ),
        );
      }
    }
    _clients[salonId] = out;
    db.commit();
  }

  @override
  Future<void> syncClientHistory(String salonId, {String? customerId, String phone = '', String name = ''}) async {
    if (!_isHola(salonId)) return;
    final path = customerId != null ? '/salons/$salonId/clients/$customerId/appointments' : '/salons/$salonId/clients/walk-in/appointments';
    final who = customerId != null ? const <String, String>{} : (phone.trim().isNotEmpty ? {'phone': phone.trim()} : {'name': name.trim()});
    if (customerId == null && who.values.first.isEmpty) return;
    for (var page = 1, pages = 1; page <= pages && page <= 20; page++) {
      final res = await api!.get(path, query: {...who, 'page': '$page', 'pageSize': '100'});
      final list = res is Map ? (res['data'] as List? ?? const []) : res as List;
      if (res is Map) pages = asInt((res['meta'] as Map?)?['totalPages'], 1);
      for (final j in list.cast<J>()) {
        // Old visits aren't news: remember their status so nothing is announced.
        _seen[j['id'] as String] = mirrorAppointment(db, j).status;
      }
    }
    db.commit();
  }

  Salon _salon(String id) => db.salons.where((s) => s.id == id).firstOrNull ?? (throw DomainError(tr('Salon not found.')));
  Appointment _appt(String id) => appointment(id) ?? (throw DomainError(tr('Appointment not found.')));
  List<ServiceItem> _services(List<String> ids) => [for (final id in ids) db.services.where((s) => s.id == id).firstOrNull ?? (throw DomainError(tr('A service is no longer offered.')))];
  String _when(Appointment a) => tr('{day} at {time}', _whenArgs(a));
  Map<String, String> _whenArgs(Appointment a) => {'day': dayLabel(a.startsAt, today), 'time': fmtTime(a.startsAt)};

  @override
  List<Slot> availability({required String branchId, required List<String> serviceIds, String? staffId, required DateTime day, String? rescheduling}) {
    final b = db.branches.where((x) => x.id == branchId).firstOrNull;
    if (b == null || serviceIds.isEmpty) return const [];
    if (_isHola(b.salonId)) return _slots[_key(branchId, serviceIds, staffId, day)] ?? const [];
    final dur = _services(serviceIds).fold(0, (s, x) => s + x.durationMin);
    return availableSlots(
      day: day,
      branch: b,
      // Only the team members who work at this branch (the first branch by default).
      staff: db.staff.where((s) => s.salonId == b.salonId && worksAt(db, s, branchId)).toList(),
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
  bool canCancelFree(Appointment a) => a.hola ? (a.freeCancelUntil == null || now().isBefore(a.freeCancelUntil!)) : _canCancelFreeHere(a);
  bool _canCancelFreeHere(Appointment a) => a.startsAt.difference(now()).inMinutes >= _salon(a.salonId).cancelWindowHours * 60;

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
    if (_isHola(salonId)) {
      // HOLA applies each service's best offer itself (contract 0.20.0).
      final key = DateTime.now().microsecondsSinceEpoch.toRadixString(36) + db.newId(); // one booking even if the request is retried
      return _remote(
        () => api!.post(
          '/appointments',
          {'branchId': branchId, 'serviceIds': serviceIds, 'staffId': ?staffId, 'startsAt': start.toUtc().toIso8601String(), if (notes.trim().isNotEmpty) 'notes': notes.trim()},
          headers: {'Idempotency-Key': key},
        ),
        codes: _slotCodes,
      );
    }
    final me = requireMe;
    final s = _salon(salonId);
    if (!s.isListed) throw DomainError(tr('This salon is not taking bookings right now.'));
    final svcs = _services(serviceIds);
    // Each service's best offer this customer can still use, checked again now
    // (an offer that ended or was switched off while choosing isn't applied).
    final offers = <ServiceOffer>[];
    var discount = 0;
    for (final x in svcs) {
      if (bestOfferOn(db, me.id, x) case final o?) {
        offers.add(o);
        discount += o.discountOn(x.price);
      }
    }
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
      price: svcs.fold(0, (t, x) => t + x.price) - discount,
      offerIds: [for (final o in offers) o.id],
      discount: discount,
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
      db.notifySalon(
        salonId,
        'New booking request',
        '{name} · {services} · {day} at {time}. Please confirm.',
        args: {'name': me.name, 'services': what, ..._whenArgs(a)},
        icon: 'cal',
        link: link,
        onlyStaffId: a.staffId,
      );
    }
    db.commit();
    return a;
  }

  @override
  Future<Appointment> walkIn({
    required String salonId,
    required String branchId,
    required String guestName,
    required String guestPhone,
    required List<String> serviceIds,
    required String staffId,
    required DateTime start,
  }) async {
    requireRole({Role.salonOwner, Role.salonStaff});
    if (requireMe.salonId != salonId) throw DomainError(tr('Not your salon.'));
    if (guestName.trim().length < 2) throw DomainError(tr("Enter the client's name."));
    if (serviceIds.isEmpty) throw DomainError(tr('Pick at least one service.'));
    // HOLA salons: the walk-in goes on HOLA's calendar, so the slot is taken
    // for online bookings too (contract 0.18.1: starts CONFIRMED).
    if (_isHola(salonId)) {
      final key = DateTime.now().microsecondsSinceEpoch.toRadixString(36) + db.newId();
      return _remote(
        () => api!.post(
          '/salons/$salonId/appointments',
          {
            'branchId': branchId,
            'serviceIds': serviceIds,
            if (staffId.isNotEmpty) 'staffId': staffId,
            'startsAt': start.toUtc().toIso8601String(),
            'guest': {'fullName': guestName.trim(), if (guestPhone.trim().isNotEmpty) 'phone': guestPhone.trim()},
          },
          headers: {'Idempotency-Key': key},
        ),
        codes: {
          ..._slotCodes,
          'APPOINTMENT_SLOT_UNAVAILABLE': tr('That professional isn’t free then (opening hours, shift or time off). Pick another time or professional.'),
          'APPOINTMENT_TOO_EARLY': tr('That time has passed. Pick a time from now on.'),
          'FORBIDDEN': tr('Only the owner or a manager can add walk-ins.'),
        },
      );
    }
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
    if (staffId != requireMe.id) {
      db.notify(
        staffId,
        'Walk-in added',
        '{name} · {services} · {day} at {time}',
        args: {'name': a.customerName, 'services': a.serviceNames.join(', '), ..._whenArgs(a)},
        icon: 'cal',
        link: NotifLink('appointment', a.id),
      );
    }
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
    if (appointment(id)?.hola == true && api != null) {
      await _remote(() => api!.post('/appointments/$id/confirm', const {}));
      return;
    }
    final a = _forSalon(id);
    _move(a, ApptStatus.confirmed, from: {ApptStatus.requested});
    _tellCustomer(a, 'Booking confirmed', '{salon} · {day} at {time}', 'check', {'salon': _salon(a.salonId).name, ..._whenArgs(a)});
    db.commit();
  }

  @override
  Future<void> decline(String id, String reason) async {
    if (appointment(id)?.hola == true && api != null) {
      if (reason.trim().isEmpty) throw DomainError(tr('Add a short reason for the client.'));
      await _remote(() => api!.post('/appointments/$id/decline', {'reason': reason.trim()}));
      return;
    }
    final a = _forSalon(id);
    _move(a, ApptStatus.declined, note: reason.trim(), from: {ApptStatus.requested});
    _tellCustomer(a, "Salon couldn't take your booking", reason.trim().isEmpty ? '{salon} · {day} at {time}' : '{salon} · {day} at {time}. {reason}', 'x', {
      'salon': _salon(a.salonId).name,
      ..._whenArgs(a),
      'reason': reason.trim(),
    });
    db.commit();
  }

  @override
  Future<void> cancel(String id, String reason) async {
    final a = _appt(id);
    if (a.hola && api != null) {
      await _remote(() => api!.post('/appointments/$id/cancel', {if (reason.trim().isNotEmpty) 'reason': reason.trim()}));
      return;
    }
    final me = requireMe;
    if (me.role == Role.customer) {
      if (a.customerId != me.id) throw DomainError(tr('Not your booking.'));
      a.lateCancel = a.status == ApptStatus.confirmed && !canCancelFree(a);
      _move(a, ApptStatus.cancelledByCustomer, note: reason.trim(), from: ApptStatus.upcoming);
      db.notifySalon(
        a.salonId,
        'Booking cancelled',
        a.lateCancel ? '{name} cancelled {day} at {time} (late).' : '{name} cancelled {day} at {time}.',
        args: {'name': a.customerName, ..._whenArgs(a)},
        icon: 'x',
        link: NotifLink('appointment', a.id),
        onlyStaffId: a.staffId,
      );
    } else {
      _forSalon(id);
      _move(a, ApptStatus.cancelledBySalon, note: reason.trim(), from: ApptStatus.upcoming);
      _tellCustomer(a, 'Booking cancelled by salon', reason.trim().isEmpty ? '{salon} · {day} at {time}' : '{salon} · {day} at {time}. {reason}', 'x', {
        'salon': _salon(a.salonId).name,
        ..._whenArgs(a),
        'reason': reason.trim(),
      });
    }
    db.commit();
  }

  @override
  Future<void> reschedule(String id, DateTime start, {String? staffId}) async {
    final a = _appt(id);
    if (a.hola && api != null) {
      await _remote(() => api!.post('/appointments/$id/reschedule', {'startsAt': start.toUtc().toIso8601String(), 'staffId': ?staffId, 'version': a.version}), codes: _slotCodes);
      return;
    }
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
      db.notifySalon(
        a.salonId,
        'Booking moved',
        '{name} moved {fromDay} at {fromTime} to {day} at {time}.',
        args: {'name': a.customerName, 'fromDay': beforeArgs['day']!, 'fromTime': beforeArgs['time']!, ..._whenArgs(a)},
        icon: 'cal',
        link: NotifLink('appointment', a.id),
        onlyStaffId: a.staffId,
      );
    } else {
      _tellCustomer(a, 'Your booking was moved', '{salon} moved it to {day} at {time}.', 'cal', {'salon': s.name, ..._whenArgs(a)});
    }
    db.commit();
  }

  @override
  Future<void> checkIn(String id) async {
    if (appointment(id)?.hola == true && api != null) {
      await _remote(() => api!.post('/appointments/$id/check-in', const {}), codes: _slotCodes);
      return;
    }
    final a = _forSalon(id);
    if (a.startsAt.difference(now()).inMinutes > _salon(a.salonId).checkInEarlyMin) throw DomainError(tr('Check-in opens 2 hours before the appointment.'));
    _move(a, ApptStatus.checkedIn, from: {ApptStatus.confirmed});
    db.commit();
  }

  @override
  Future<void> startService(String id) async {
    if (appointment(id)?.hola == true && api != null) {
      await _remote(() => api!.post('/appointments/$id/start', const {}));
      return;
    }
    final a = _forSalon(id);
    _move(a, ApptStatus.inService, from: {ApptStatus.checkedIn, ApptStatus.confirmed});
    db.commit();
  }

  @override
  Future<void> complete(String id) async {
    if (appointment(id)?.hola == true && api != null) {
      await _remote(() => api!.post('/appointments/$id/complete', const {}));
      return;
    }
    final a = _forSalon(id);
    _move(a, ApptStatus.completed, from: {ApptStatus.inService, ApptStatus.checkedIn});
    _tellCustomer(a, 'How was your visit?', 'Rate {salon} and help others choose.', 'star', {'salon': _salon(a.salonId).name});
    db.commit();
  }

  @override
  Future<void> noShow(String id) async {
    if (appointment(id)?.hola == true && api != null) {
      await _remote(() => api!.post('/appointments/$id/no-show', const {}), codes: _slotCodes);
      return;
    }
    final a = _forSalon(id);
    if (!canMarkNoShow(a)) throw DomainError(tr('You can mark a no-show {n} minutes after the start time.', {'n': _salon(a.salonId).noShowGraceMin}));
    _move(a, ApptStatus.noShow, from: {ApptStatus.confirmed});
    _tellCustomer(a, 'Marked as no-show', '{salon} · {day} at {time}', 'alert', {'salon': _salon(a.salonId).name, ..._whenArgs(a)});
    db.commit();
  }
}

/// Whether [p] works at [branchId]: their own branch, or the salon's first one.
bool worksAt(LocalDatabase db, StaffProfile p, String branchId) => (p.branchId ?? db.branches.where((b) => b.salonId == p.salonId && !b.id.endsWith('~delivery')).firstOrNull?.id) == branchId;
