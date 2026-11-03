import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import '../network/api.dart';

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

  Future<void> start() async {
    api.beforeLogout = unregister;
    await _fm.setAutoInitEnabled(true);
    _fm.onTokenRefresh.listen((t) {
      if (auth.current != null) _register(token: t);
    });
    FirebaseMessaging.onMessage.listen((m) {
      final (title, body, link) = _read(m);
      engage.receivePush(title, body, link: link);
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
    engage.receivePush(title, body, link: link);
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
    _accountId = id;
    if (id != null && auth.usesServer) _register();
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
      await _fm.requestPermission();
      token ??= await _fm.getToken();
      if (token == null || auth.current == null) return;
      final saved = await _saved();
      final me = auth.current!.id;
      if (saved != null && saved['token'] == token && saved['account'] == me) return;
      // A rotated token or another account: drop the old registration first.
      if (saved?['id'] != null) await _delete(saved!['id']!);
      final r = await api.post('/me/devices', {'platform': Platform.isIOS ? 'ios' : 'android', 'fcmToken': token, 'appVersion': kAppVersion});
      final j = r is Map ? (r['data'] is Map ? r['data'] as Map : r) : const {};
      final id = '${j['id'] ?? ''}';
      await _secure.write(key: _key, value: jsonEncode({'id': id, 'token': token, 'account': me}));
      debugPrint('Push: registered device $id');
    } catch (e) {
      debugPrint('Push: registration failed: $e ${e is ApiError ? e.fields : ''}');
    }
  }

  /// Removes this phone from the server and drops the token, so a signed-out
  /// phone gets nothing even if the server call fails.
  Future<void> unregister() async {
    _accountId = null;
    try {
      final saved = await _saved();
      if (saved?['id'] != null) await _delete(saved!['id']!);
      await _secure.delete(key: _key);
      await _fm.deleteToken();
    } catch (e) {
      debugPrint('Push: unregister failed: $e');
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
    'certificate' => 'training', // id is the certificate number; open its session
    _ => null,
  };
  if (kind == null) return null;
  final id = kind == 'training' ? '${d['sessionId'] ?? d['id'] ?? ''}' : '${d['id'] ?? ''}';
  // Complaints and reviews open their lists; the rest need the entity.
  if (id.isEmpty && kind != 'complaint' && kind != 'review' && kind != 'offers') return null;
  return NotifLink(kind, id);
}
