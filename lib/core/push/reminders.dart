import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/entities/entities.dart';
import '../l10n/l10n.dart';
import '../utils/clock.dart';
import '../utils/format.dart';

/// One reminder to schedule: the booking and what to show.
class ReminderInfo {
  const ReminderInfo({required this.appointment, required this.salonName, required this.mapsUrl});
  final Appointment appointment;
  final String salonName;

  /// Google Maps link to the branch, for the Directions button.
  final String mapsUrl;
}

/// What a tapped reminder asks for.
class ReminderTap {
  const ReminderTap(this.appointmentId, {this.action, this.mapsUrl = ''});
  final String appointmentId;

  /// null (the notification itself), [Reminders.directions] or [Reminders.cancel].
  final String? action;
  final String mapsUrl;
}

/// Booking reminders 24 hours and 2 hours before a visit, scheduled on the
/// phone (they arrive even without signal), with "Directions" and "Cancel
/// booking" buttons. A reminder HOLA pushes for the same visit replaces the
/// phone's own (same notification id), so there is never a duplicate.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  static const directions = 'directions', cancel = 'cancel';

  /// The iPhone reminder category (same id as HOLA's reminder pushes).
  static const iosCategory = 'APPOINTMENT_REMINDER';
  static const _channel = 'hola_reminders';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void>? _starting;

  /// The reminder (or one of its buttons) the customer tapped, until handled.
  final tapped = ValueNotifier<ReminderTap?>(null);

  /// Reminders scheduled during this run: notification id → booking signature.
  final _scheduled = <int, String>{};

  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Karachi')); // HOLA runs on Pakistan time
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
          // iPhone: HOLA's push sign-up asks for permission; here only the
          // reminder's buttons (category APPOINTMENT_REMINDER, as HOLA sends).
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: [
              DarwinNotificationCategory(
                iosCategory,
                actions: [
                  DarwinNotificationAction.plain(directions, tr('Directions'), options: {DarwinNotificationActionOption.foreground}),
                  DarwinNotificationAction.plain(cancel, tr('Cancel booking'), options: {DarwinNotificationActionOption.foreground, DarwinNotificationActionOption.destructive}),
                ],
              ),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: _onResponse,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true && launch!.notificationResponse != null) _onResponse(launch.notificationResponse!);
      _ready = true;
    } catch (e) {
      debugPrint('Reminders: not available: $e'); // e.g. in tests
    }
  }

  void _onResponse(NotificationResponse r) {
    try {
      final j = jsonDecode(r.payload ?? '{}') as Map;
      final id = '${j['id'] ?? ''}';
      if (id.isEmpty) return;
      tapped.value = ReminderTap(id, action: r.actionId, mapsUrl: '${j['maps'] ?? ''}');
    } catch (_) {}
  }

  /// Notification id of one reminder (stable across runs).
  static int idFor(String appointmentId, String kind) => '$appointmentId|$kind'.hashCode & 0x7fffffff;

  NotificationDetails _details() => NotificationDetails(
    android: AndroidNotificationDetails(
      _channel,
      tr('Booking reminders'),
      channelDescription: tr('A reminder the day before and 2 hours before your visit'),
      importance: Importance.high,
      priority: Priority.high,
      actions: [AndroidNotificationAction(directions, tr('Directions'), showsUserInterface: true), AndroidNotificationAction(cancel, tr('Cancel booking'), showsUserInterface: true)],
    ),
    iOS: const DarwinNotificationDetails(categoryIdentifier: iosCategory, presentAlert: true, presentBanner: true, presentList: true, presentSound: true),
  );

  (String, String) _text(ReminderInfo r, String kind) {
    final a = r.appointment;
    final when = fmtTime(a.startsAt);
    final title = kind == '24h' ? tr('Tomorrow at {time} · {salon}', {'time': when, 'salon': r.salonName}) : tr('In 2 hours: {time} · {salon}', {'time': when, 'salon': r.salonName});
    return (title, a.serviceNames.join(', '));
  }

  String _payload(ReminderInfo r) => jsonEncode({'id': r.appointment.id, 'maps': r.mapsUrl});

  /// Brings the phone's reminders in line with the customer's bookings:
  /// upcoming visits get theirs, cancelled or past ones lose them.
  Future<void> sync(List<ReminderInfo> bookings) async {
    await start();
    if (!_ready) return;
    final t = now();
    final keep = <int>{};
    for (final r in bookings) {
      final a = r.appointment;
      final upcoming = ApptStatus.upcoming.contains(a.status) && a.startsAt.isAfter(t);
      for (final (kind, before) in const [('24h', Duration(hours: 24)), ('2h', Duration(hours: 2))]) {
        final id = idFor(a.id, kind);
        final at = a.startsAt.subtract(before);
        if (!upcoming || !at.isAfter(t)) {
          if (_scheduled.remove(id) != null || !upcoming) await _plugin.cancel(id: id);
          continue;
        }
        keep.add(id);
        // Re-schedule only when the time, salon, services or language changed.
        final sig = '${a.startsAt.toIso8601String()}|${r.salonName}|${a.serviceNames.join(',')}|${L10n.lang.value}';
        if (_scheduled[id] == sig) continue;
        final (title, body) = _text(r, kind);
        try {
          await _plugin.zonedSchedule(
            id: id,
            scheduledDate: tz.TZDateTime.from(at, tz.local),
            notificationDetails: _details(),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: title,
            body: body,
            payload: _payload(r),
          );
          _scheduled[id] = sig;
        } catch (e) {
          debugPrint('Reminders: could not schedule ${a.code}: $e');
        }
      }
    }
    // Bookings that left the list (e.g. signed out) lose their reminders.
    for (final id in _scheduled.keys.where((id) => !keep.contains(id)).toList()) {
      _scheduled.remove(id);
      await _plugin.cancel(id: id);
    }
  }

  /// Drops both reminders of one booking (it changed on the server: cancelled,
  /// moved, confirmed). The next sync puts them back if still due.
  Future<void> cancelFor(String appointmentId) async {
    await start();
    if (!_ready) return;
    for (final kind in const ['24h', '2h']) {
      final id = idFor(appointmentId, kind);
      _scheduled.remove(id);
      await _plugin.cancel(id: id);
    }
  }

  /// Forgets what this run scheduled, so the next [sync] re-checks every
  /// booking (another part of the app may have cancelled some).
  void forgetScheduled() => _scheduled.clear();

  /// Clears every reminder (sign-out).
  Future<void> clear() async {
    _scheduled.clear();
    if (_ready) await _plugin.cancelAll();
  }

  /// Shows a reminder HOLA pushed (data-only), with the buttons; it takes the
  /// place of the phone's own reminder for the same visit.
  Future<void> showPushed({required String appointmentId, required String kind, required String title, required String body, String mapsUrl = ''}) async {
    await start();
    if (!_ready) return;
    // HOLA's 2-hour reminder takes the place of the day-before one.
    if (kind == '2h') await _plugin.cancel(id: idFor(appointmentId, '24h'));
    await _plugin.show(id: idFor(appointmentId, kind), title: title, body: body, notificationDetails: _details(), payload: jsonEncode({'id': appointmentId, 'maps': mapsUrl}));
  }
}
