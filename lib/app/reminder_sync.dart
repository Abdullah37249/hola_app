import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/push/push_events.dart';
import '../core/push/reminders.dart';
import '../domain/entities/entities.dart';
import '../domain/repositories/repositories.dart';

/// Keeps the phone's booking reminders in step with the signed-in customer's
/// bookings: a new, moved or cancelled booking updates them; signing out (or
/// another role) clears them.
class ReminderSync with WidgetsBindingObserver {
  ReminderSync(BuildContext context)
    : _auth = context.read<AuthRepository>(),
      _bookings = context.read<BookingRepository>(),
      _salons = context.read<SalonRepository>(),
      _engage = context.read<EngagementRepository>() {
    _bookings.changes.addListener(_soon);
    _auth.changes.addListener(_soon);
    _engage.changes.addListener(_soon);
    WidgetsBinding.instance.addObserver(this);
    // A booking push may have dropped reminders: re-check all once data is fresh.
    _pushes = pushEvents.stream.listen((type) {
      if (type == 'appointment' || type == 'appointment_reminder') _force();
    });
    _soon();
  }
  StreamSubscription<String>? _pushes;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the app: a closed-app push may have removed reminders.
    if (state == AppLifecycleState.resumed) _force();
  }

  void _force() {
    _last = '';
    Reminders.instance.forgetScheduled();
    _soon();
  }

  final AuthRepository _auth;
  final EngagementRepository _engage;
  final BookingRepository _bookings;
  final SalonRepository _salons;
  Timer? _t;
  String _last = '';

  void _soon() {
    _t?.cancel();
    _t = Timer(const Duration(seconds: 2), _run);
  }

  Future<void> _run() async {
    final me = _auth.current;
    // Signed out, another role, or reminders switched off: none on this phone.
    if (me == null || me.role != Role.customer || !_engage.remindersOn) {
      if (_last != 'none') await Reminders.instance.clear();
      _last = 'none';
      return;
    }
    final list = _bookings.forCustomer(me.id);
    // Nothing that matters changed: leave the schedule alone.
    final sig = list.map((a) => '${a.id}${a.status}${a.startsAt.millisecondsSinceEpoch}').join('|');
    if (sig == _last) return;
    _last = sig;
    await Reminders.instance.sync([
      for (final a in list) ReminderInfo(appointment: a, salonName: _salons.salon(a.salonId)?.name ?? '', mapsUrl: mapsLink(_salons.branch(a.branchId), _salons.salon(a.salonId)?.name ?? '')),
    ]);
  }

  void dispose() {
    _t?.cancel();
    _bookings.changes.removeListener(_soon);
    _auth.changes.removeListener(_soon);
    _engage.changes.removeListener(_soon);
    WidgetsBinding.instance.removeObserver(this);
    _pushes?.cancel();
  }
}

/// Google Maps directions to a branch: HOLA's link, its GPS point, or its address.
String mapsLink(Branch? b, String salonName) {
  if (b == null) return '';
  if (b.mapsUrl case final u? when u.isNotEmpty) return u;
  if (b.location case final g?) return 'https://www.google.com/maps/dir/?api=1&destination=${g.lat},${g.lng}';
  final q = Uri.encodeComponent([salonName, b.address, b.area, b.city].where((x) => x.isNotEmpty).join(', '));
  return 'https://www.google.com/maps/search/?api=1&query=$q';
}
