import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../network/api.dart';
import 'push_events.dart';
import 'reminders.dart';

// HOLA's server sends to classic FCM registration tokens, so this uses
// getToken/onTokenRefresh/deleteToken. The newer register()/onRegistered API
// hands out installation ids, which the server would have to support first.
// ignore_for_file: deprecated_member_use

/// Push notifications from HOLA (Firebase Cloud Messaging).
///
/// Registers this phone with the server (POST /me/devices) after sign-in and
/// whenever Firebase rotates the token, and removes it (DELETE
/// /me/devices/:id) before sign-out. Pushes that arrive while the app is open
/// go into the in-app list; a tapped push becomes a [NotifLink] in [opened].
class PushService {
  PushService({required this.api, required this.auth, required this.engage});
  final HolaApi api;
  final AuthRepository auth;
  final EngagementRepository engage;

  /// A tapped push waiting to be opened once the app is signed in.
  final opened = ValueNotifier<NotifLink?>(null);

  /// Called for a push that arrives while the app is on screen.
  void Function(String title, String body, NotifLink? link)? onForeground;

  static const _key = 'hola.pushDevice';
  final _secure = const FlutterSecureStorage();
  FirebaseMessaging get _fm => FirebaseMessaging.instance;
  String? _accountId;
  Future<void>? _registering;

  /// "account|token" registered with HOLA during this run of the app.
  String? _done;

  Future<void> start() async {
    api.beforeLogout = unregister;
    await _fm.setAutoInitEnabled(true);
    // iPhone hides pushes while the app is open unless told otherwise: show
    // the banner with sound, as people expect on iOS (Android shows a toast).
    if (Platform.isIOS) await _fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    _fm.onTokenRefresh.listen((t) {
      if (auth.current != null) _register(token: t);
    });
    FirebaseMessaging.onMessage.listen((m) {
      final (title, body, link) = _read(m);
      if ('${m.data['type']}' == 'appointment_reminder') showReminderPush(m.data);
      // A booking changed elsewhere: its phone reminders wait for the fresh copy.
      if ('${m.data['type']}' == 'appointment' && '${m.data['id'] ?? ''}'.isNotEmpty) Reminders.instance.cancelFor('${m.data['id']}');
      pushEvents.add('${m.data['type'] ?? ''}');
      engage.receivePush(title, body, link: link, inboxId: m.data['notificationId'] as String?);
      onForeground?.call(title, body, link);
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_tapped);
    final first = await _fm.getInitialMessage();
    if (first != null) _tapped(first);
    auth.changes.addListener(_onAuth);
    _onAuth();
  }

  void _tapped(RemoteMessage m) {
    final (title, body, link) = _read(m);
    pushEvents.add('${m.data['type'] ?? ''}');
    engage.receivePush(title, body, link: link, inboxId: m.data['notificationId'] as String?);
    final inboxId = m.data['notificationId'];
    if (inboxId != null && '$inboxId'.isNotEmpty) {
      api.post('/me/notifications/$inboxId/read', const {}).catchError((Object e) {
        debugPrint('Push: could not mark $inboxId read: $e');
      });
    }
    if (link != null) opened.value = link;
  }

  void _onAuth() {
    final id = auth.current?.id;
    if (id == _accountId) return;
    final was = _accountId;
    _accountId = id;
    if (id != null && auth.usesServer) _register();
    // Signed out without the normal sign-out (session expired, or kept for
    // fingerprint sign-in): drop this phone's push token so that account's
    // pushes stop reaching the lock screen. Signing in again registers anew.
    if (id == null && was != null) _dropToken();
  }

  /// One registration at a time; a token refresh during one waits for it.
  Future<void> _register({String? token}) async {
    final prev = _registering;
    if (prev != null) await prev;
    final run = _doRegister(token);
    _registering = run;
    try {
      await run;
    } finally {
      if (identical(_registering, run)) _registering = null;
    }
  }

  Future<void> _doRegister(String? token) async {
    try {
      // Android 13+ and iOS ask the user once; a "no" still registers the
      // token, so turning notifications on later in Settings just works.
      final perm = await _fm.requestPermission();
      debugPrint('Push: permission ${perm.authorizationStatus.name}');
      // iPhone: Firebase hands out its token only once Apple's push token has
      // arrived, which can take a few seconds after the first launch.
      if (token == null && Platform.isIOS) {
        for (var i = 0; i < 10 && await _fm.getAPNSToken() == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      token ??= await _fm.getToken();
      if (token == null || auth.current == null) return;
      final saved = await _saved();
      final me = auth.current!.id;
      // Registered already in this run of the app. Otherwise always tell HOLA
      // again (it's an upsert): the server may have dropped this phone, e.g.
      // after another account used it, and a stale local record would then
      // leave the account without pushes.
      if (_done == '$me|$token') return;
      // A rotated token or another account: drop the old registration first.
      if (saved?['id'] != null && (saved!['token'] != token || saved['account'] != me)) await _delete(saved['id']!);
      final r = await api.post('/me/devices', {'platform': Platform.isIOS ? 'ios' : 'android', 'fcmToken': token, 'appVersion': kAppVersion});
      final j = r is Map ? (r['data'] is Map ? r['data'] as Map : r) : const {};
      final id = '${j['id'] ?? ''}';
      await _secure.write(key: _key, value: jsonEncode({'id': id, 'token': token, 'account': me}));
      _done = '$me|$token';
      debugPrint('Push: registered device $id');
    } catch (e) {
      debugPrint('Push: registration failed: $e ${e is ApiError ? e.fields : ''}');
    }
  }

  /// Removes this phone from the server and drops the token, so a signed-out
  /// phone gets nothing even if the server call fails.
  Future<void> unregister() async {
    _accountId = null;
    _done = null;
    try {
      final saved = await _saved();
      if (saved?['id'] != null) await _delete(saved!['id']!);
      await _secure.delete(key: _key);
      await _fm.deleteToken();
    } catch (e) {
      debugPrint('Push: unregister failed: $e');
    }
  }

  Future<void> _dropToken() async {
    _done = null;
    try {
      await _secure.delete(key: _key);
      await _fm.deleteToken();
    } catch (e) {
      debugPrint('Push: could not drop token: $e');
    }
  }

  Future<void> _delete(String id) async {
    if (id.isEmpty) return;
    try {
      await api.delete('/me/devices/$id');
    } catch (e) {
      debugPrint('Push: could not remove device $id: $e');
    }
  }

  Future<Map<String, String>?> _saved() async {
    try {
      final v = await _secure.read(key: _key);
      if (v == null) return null;
      return {for (final e in (jsonDecode(v) as Map).entries) '${e.key}': '${e.value}'};
    } catch (_) {
      return null;
    }
  }

  (String, String, NotifLink?) _read(RemoteMessage m) {
    final d = m.data;
    final title = m.notification?.title ?? '${d['title'] ?? ''}';
    final body = m.notification?.body ?? '${d['body'] ?? ''}';
    return (title, body, pushLink(d));
  }
}

/// Where a push should open, from its `data` (all strings): `type` is the
/// entity kind and `id` its uuid. HOLA sends order, appointment, complaint,
/// training_session, review, campaign, broadcast and test; the last three
/// have no screen in the app, so they only show in the list.
NotifLink? pushLink(Map<String, dynamic> d) {
  final kind = switch ('${d['type'] ?? ''}') {
    'order' => 'order',
    'appointment' => 'appointment',
    'complaint' => 'complaint',
    'training_session' => 'training',
    'review' => 'review',
    'payment_request' => 'payment',
    'coupon' => 'offers',
    'offer' => 'service_offer', // a salon offer is free to use again
    'credit_collection' => 'collection', // a salon chose this rider to pay
    'chat_message' => 'chat', // id is the conversation
    'message' => 'chat', // HOLA ↔ salon chat (0.23.0): conversationId
    'return' => 'return', // a return request moved on (0.23.0): returnId
    'return_pickup' => 'return', // a rider was sent to collect returned goods
    'appointment_reminder' => 'appointment', // a visit tomorrow or in 2 hours
    'certificate' => 'training', // id is the certificate number; open its session
    _ => null,
  };
  if (kind == null) return null;
  final id = switch (kind) {
    'training' => '${d['sessionId'] ?? d['id'] ?? ''}',
    'chat' => '${d['conversationId'] ?? d['id'] ?? ''}',
    'return' => '${d['returnId'] ?? d['id'] ?? ''}',
    _ => '${d['id'] ?? ''}',
  };
  // Complaints and reviews open their lists; the rest need the entity.
  if (id.isEmpty && kind != 'complaint' && kind != 'review' && kind != 'offers' && kind != 'service_offer') return null;
  return NotifLink(kind, id);
}

/// A booking reminder HOLA pushed as data only: drawn by the app so it has
/// the Directions and Cancel buttons, in place of the phone's own reminder.
Future<void> showReminderPush(Map<String, dynamic> d) {
  final id = '${d['id'] ?? ''}';
  if (id.isEmpty) return Future.value();
  return Reminders.instance.showPushed(appointmentId: id, kind: '${d['kind'] ?? '2h'}', title: '${d['title'] ?? ''}', body: '${d['body'] ?? ''}', mapsUrl: '${d['mapsUrl'] ?? ''}');
}

/// Pushes that arrive while the app is closed. Normal pushes are shown by
/// Android itself; only reminders need the app to draw them.
@pragma('vm:entry-point')
Future<void> pushInBackground(RemoteMessage m) async {
  final type = '${m.data['type']}', id = '${m.data['id'] ?? ''}';
  if (type == 'appointment_reminder') await showReminderPush(m.data);
  // The salon cancelled, moved or confirmed a booking while the app was closed:
  // drop the phone's own reminders for it (HOLA's own reminders still come if
  // the visit is on). The app schedules them again from fresh data when opened.
  if (type == 'appointment' && id.isNotEmpty) await Reminders.instance.cancelFor(id);
}
