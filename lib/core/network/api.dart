import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import '../utils/network_status.dart';
import '../../domain/repositories/repositories.dart' show DomainError;

typedef J = Map<String, dynamic>;

/// Sent with the push registration; keep in step with pubspec.yaml.
const kAppVersion = '0.1.0';

/// HOLA API base (staging until production is announced).
const kHolaApi = 'https://hola.metaxperts.net/api/v1';

/// A problem+json error from the server (RFC 9457). Branch on [code].
class ApiError implements Exception {
  final int status;
  final String code, detail;

  /// Field path → message, for 422 VALIDATION_FAILED.
  final Map<String, String> fields;
  const ApiError(this.status, this.code, this.detail, [this.fields = const {}]);
  @override
  String toString() => 'ApiError($status $code: $detail)';
}

/// Access and refresh tokens from TokenResponse.
class Tokens {
  final String access, refresh;
  final DateTime accessExpires, refreshExpires;
  const Tokens(this.access, this.refresh, this.accessExpires, this.refreshExpires);

  factory Tokens.fromJson(J j) => Tokens(j['accessToken'], j['refreshToken'], DateTime.parse(j['accessTokenExpiresAt']), DateTime.parse(j['refreshTokenExpiresAt']));
  J toJson() => {'accessToken': access, 'refreshToken': refresh, 'accessTokenExpiresAt': accessExpires.toIso8601String(), 'refreshTokenExpiresAt': refreshExpires.toIso8601String()};
}

/// Where tokens live. HOLA requires the phone's Keystore/Keychain.
abstract class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens t);
  Future<void> clear();

  /// Sessions kept for fingerprint sign-in after signing out, one per account.
  Future<Tokens?> readParked(String accountId);
  Future<void> writeParked(String accountId, Tokens t);
  Future<void> clearParked(String accountId);
}

class SecureTokenStore implements TokenStore {
  static const _key = 'hola.tokens', _parked = 'hola.tokens.fingerprint';
  static String _for(String accountId) => '$_parked.$accountId';
  final _s = const FlutterSecureStorage();
  Future<Tokens?> _get(String k) async {
    final v = await _s.read(key: k);
    return v == null ? null : Tokens.fromJson(jsonDecode(v) as J);
  }

  @override
  Future<Tokens?> read() => _get(_key);
  @override
  Future<void> write(Tokens t) => _s.write(key: _key, value: jsonEncode(t.toJson()));
  @override
  Future<void> clear() => _s.delete(key: _key);
  @override
  Future<Tokens?> readParked(String accountId) async {
    // Builds before per-account fingerprints kept one session under the bare key.
    final legacy = await _get(_parked);
    if (legacy != null) {
      await _s.write(key: _for(accountId), value: jsonEncode(legacy.toJson()));
      await _s.delete(key: _parked);
    }
    return _get(_for(accountId));
  }

  @override
  Future<void> writeParked(String accountId, Tokens t) => _s.write(key: _for(accountId), value: jsonEncode(t.toJson()));
  @override
  Future<void> clearParked(String accountId) => _s.delete(key: _for(accountId));
}

class MemoryTokenStore implements TokenStore {
  Tokens? t;
  final parked = <String, Tokens>{};
  @override
  Future<Tokens?> read() async => t;
  @override
  Future<void> write(Tokens v) async => t = v;
  @override
  Future<void> clear() async => t = null;
  @override
  Future<Tokens?> readParked(String accountId) async => parked[accountId];
  @override
  Future<void> writeParked(String accountId, Tokens v) async => parked[accountId] = v;
  @override
  Future<void> clearParked(String accountId) async => parked.remove(accountId);
}

/// Thin JSON client for the HOLA API: bearer tokens, one-at-a-time refresh
/// (refresh tokens rotate, and replaying an old one ends the session), and
/// problem+json errors turned into [ApiError].
class HolaApi {
  HolaApi({http.Client? client, TokenStore? tokens, this.base = kHolaApi}) : _http = client ?? http.Client(), _store = tokens ?? SecureTokenStore();

  final http.Client _http;
  final TokenStore _store;
  final String base;
  Tokens? _tokens;
  bool _loaded = false;
  Future<void>? _refreshing;

  /// Called when the session can't be renewed (refresh token expired or revoked).
  void Function()? onSessionEnded;

  /// Runs before /auth/logout while the tokens still work (removes this
  /// phone's push registration).
  Future<void> Function()? beforeLogout;

  Future<Tokens?> _current() async {
    if (!_loaded) {
      try {
        _tokens = await _store.read();
      } catch (_) {
        _tokens = null;
      }
      _loaded = true;
    }
    return _tokens;
  }

  Future<bool> get hasSession async => (await _current()) != null;

  Future<void> _save(J tokenResponse) async {
    _tokens = Tokens.fromJson(tokenResponse);
    _loaded = true;
    await _store.write(_tokens!);
  }

  Future<void> clearSession() async {
    _tokens = null;
    _loaded = true;
    await _store.clear();
  }

  // ── auth ──

  Future<void> login(String email, String password) async => _save(await post('/auth/login', {'email': email, 'password': password, 'deviceName': 'HOLA app'}, auth: false));

  Future<void> register({required String email, required String password, required String fullName, String? phone}) async =>
      _save(await post('/auth/register', {'email': email, 'password': password, 'fullName': fullName, if (phone != null) 'phone': phone}, auth: false));

  /// A salon signs itself up: creates the owner and a live salon, signed in at once.
  Future<void> registerSalon({required String email, required String password, required String fullName, String? phone, required Map<String, Object?> salon}) async =>
      _save(await post('/auth/register-salon', {'email': email, 'password': password, 'fullName': fullName, if (phone != null) 'phone': phone, 'salon': salon}, auth: false));

  Future<void> logout() async {
    try {
      if (await hasSession) {
        await beforeLogout?.call();
        await post('/auth/logout', const {});
      }
    } catch (_) {
      // Signing out on the phone always works, even offline.
    }
    await clearSession();
  }

  // ── fingerprint sign-in ──
  // Signing out with fingerprint sign-in on keeps the session (in the phone's
  // encrypted storage) instead of ending it; a fingerprint brings it back.
  // The password is never stored.

  /// Signs out on this phone but keeps [accountId]'s session for its
  /// fingerprint sign-in.
  Future<void> parkSession(String accountId) async {
    final t = await _current();
    if (t == null) return;
    try {
      await beforeLogout?.call(); // no pushes for a signed-out phone
    } catch (_) {}
    await _store.writeParked(accountId, t);
    await clearSession();
  }

  Future<bool> hasParked(String accountId) async {
    try {
      return await _store.readParked(accountId) != null;
    } catch (_) {
      return false;
    }
  }

  /// Brings [accountId]'s kept session back and renews it with HOLA. Throws
  /// [ApiError] 401 when HOLA has ended it (it's then forgotten), or a network
  /// error (it's kept, renewed if the renewal got through, for another try).
  Future<void> resumeParked(String accountId) async {
    final t = await _store.readParked(accountId);
    if (t == null) throw const ApiError(401, 'UNAUTHENTICATED', 'No saved session');
    _tokens = t;
    _loaded = true;
    try {
      await refresh();
    } on ApiError catch (e) {
      if (e.status == 401) await _store.clearParked(accountId);
      _tokens = null;
      rethrow;
    } catch (_) {
      _tokens = null;
      rethrow;
    }
    // Refresh tokens rotate: keep the new one until sign-in has finished.
    await _store.writeParked(accountId, _tokens!);
  }

  /// Sign-in finished (or a fresh password sign-in): the kept copy goes.
  Future<void> forgetParked(String accountId) async {
    try {
      await _store.clearParked(accountId);
    } catch (_) {}
  }

  /// Fingerprint sign-in turned off: forget the kept session, and end it on
  /// HOLA when no one is signed in on this phone.
  Future<void> dropParked(String accountId) async {
    Tokens? t;
    try {
      t = await _store.readParked(accountId);
    } catch (_) {}
    if (t == null) return;
    await forgetParked(accountId);
    if (await hasSession) return;
    _tokens = t;
    _loaded = true;
    try {
      await post('/auth/logout', const {});
    } catch (_) {}
    await clearSession();
  }

  Future<void> _refresh() async {
    final t = await _current();
    if (t == null) throw const ApiError(401, 'UNAUTHENTICATED', 'Not signed in');
    try {
      await _save(await _send('POST', '/auth/refresh', {'refreshToken': t.refresh}, auth: false));
    } on ApiError catch (e) {
      if (e.status == 401) {
        await clearSession();
        onSessionEnded?.call();
      }
      rethrow;
    }
  }

  /// Runs at most one refresh at a time; callers wait for the same one.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  // ── requests ──

  Future<dynamic> get(String path, {Map<String, String>? query, bool auth = true}) => _authed('GET', path, null, auth, query);
  Future<dynamic> post(String path, Object? body, {bool auth = true, Map<String, String>? headers}) => _authed('POST', path, body, auth, null, headers);
  Future<dynamic> put(String path, [Object? body]) => _authed('PUT', path, body, true);
  Future<dynamic> patch(String path, Object? body) => _authed('PATCH', path, body, true);

  /// Uploads a file in HOLA's two steps (declare it, then send the bytes)
  /// and returns its id.
  Future<String> uploadFile(List<int> bytes, {required String contentType, required String purpose, String? fileName}) async {
    final f = await post('/files', {'purpose': purpose, 'contentType': contentType, 'sizeBytes': bytes.length, 'fileName': ?fileName}) as J;
    final id = f['id'] as String;
    await _authed('PUT', '/files/$id/content', _Bytes(bytes, contentType), true);
    return id;
  }

  /// Raw bytes of a file (e.g. GET /files/{id}/content), signed in.
  Future<List<int>> bytes(String path) async {
    Future<http.Response> go() async {
      final req = http.Request('GET', Uri.parse('$base$path'));
      if (_tokens != null) req.headers['authorization'] = 'Bearer ${_tokens!.access}';
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
    }

    final t = await _current();
    if (t == null) throw const ApiError(401, 'UNAUTHENTICATED', 'Not signed in');
    if (t.accessExpires.isBefore(DateTime.now().add(const Duration(seconds: 30)))) await refresh();
    var res = await go();
    if (res.statusCode == 401) {
      await refresh();
      res = await go();
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    throw ApiError(res.statusCode, 'HTTP_${res.statusCode}', 'Could not load the file');
  }

  Future<dynamic> delete(String path) => _authed('DELETE', path, null, true);

  Future<dynamic> _authed(String method, String path, Object? body, bool auth, [Map<String, String>? query, Map<String, String>? headers]) async {
    if (!auth) return _send(method, path, body, query: query, auth: false, headers: headers);
    final t = await _current();
    if (t == null) throw const ApiError(401, 'UNAUTHENTICATED', 'Not signed in');
    // Renew a little before expiry so requests don't fail mid-flight.
    if (t.accessExpires.isBefore(DateTime.now().add(const Duration(seconds: 30)))) await refresh();
    try {
      return await _send(method, path, body, query: query, headers: headers);
    } on ApiError catch (e) {
      if (e.status != 401) rethrow;
      await refresh();
      return _send(method, path, body, query: query, headers: headers);
    }
  }

  Future<dynamic> _send(String method, String path, Object? body, {Map<String, String>? query, bool auth = true, Map<String, String>? headers}) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final req = http.Request(method, uri)..headers['accept'] = 'application/json';
    if (headers != null) req.headers.addAll(headers);
    if (auth && _tokens != null) req.headers['authorization'] = 'Bearer ${_tokens!.access}';
    if (body is _Bytes) {
      req.headers['content-type'] = body.contentType;
      req.bodyBytes = body.bytes;
    } else if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    } on SocketException {
      NetworkStatus.online.value = false;
      throw const ApiError(0, 'NETWORK', 'No connection');
    } on TimeoutException {
      throw const ApiError(0, 'TIMEOUT', 'The server took too long');
    } on http.ClientException {
      NetworkStatus.online.value = false;
      throw const ApiError(0, 'NETWORK', 'No connection');
    }
    NetworkStatus.online.value = true;
    final text = utf8.decode(res.bodyBytes);
    final data = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final j = data is Map ? data : const {};
    throw ApiError(res.statusCode, j['code'] as String? ?? 'HTTP_${res.statusCode}', j['detail'] as String? ?? j['title'] as String? ?? '', {
      for (final e in (j['errors'] as List? ?? const []))
        if (e is Map) '${e['path']}': '${e['message']}',
    });
  }
}

/// Local midnight (or any local time) as ISO 8601 with the phone's offset,
/// e.g. 2026-11-02T00:00:00+05:00, as the HOLA API expects for ranges.
String isoWithOffset(DateTime local) {
  final o = local.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  String two(int n) => n.abs().toString().padLeft(2, '0');
  final base = local.toIso8601String().split('.').first;
  return '$base$sign${two(o.inHours)}:${two(o.inMinutes % 60)}';
}

/// Raw file bytes for an upload body.
class _Bytes {
  final List<int> bytes;
  final String contentType;
  const _Bytes(this.bytes, this.contentType);
}

/// A server error as the message people see, on the right form field.
/// [fieldNames] maps API paths (e.g. fullName) to the app's field names.
DomainError apiToDomain(Object e, {Map<String, String> fieldNames = const {}}) {
  if (e is DomainError) return e;
  if (e is! ApiError) return DomainError(tr('Something went wrong. Please try again.'));
  return switch (e.code) {
    'NETWORK' => DomainError(tr('Can’t reach HOLA. Check your connection and try again.')),
    'TIMEOUT' => DomainError(tr('HOLA is taking too long to answer. Try again.')),
    'INVALID_CREDENTIALS' => DomainError(tr('Email or password is incorrect.'), field: 'password'),
    // 5 wrong passwords in a row: HOLA locks sign-in for 15 minutes.
    'ACCOUNT_LOCKED' || 'LOGIN_LOCKED' => DomainError(tr('Too many failed login attempts. Please try again after 15 minutes.'), field: 'password'),
    'ACCOUNT_SUSPENDED' => DomainError(tr('This account is suspended. Contact HOLA.')),
    'EMAIL_TAKEN' => DomainError(tr('An account with this email already exists.'), field: 'email'),
    'SESSION_EXPIRED' || 'UNAUTHENTICATED' => DomainError(tr('Please sign in again.')),
    'VALIDATION_FAILED' => _validation(e, fieldNames),
    // Booking and upload limits say what the limit is: show HOLA's words.
    _ when e.status == 429 => DomainError(e.code == 'RATE_LIMITED' && e.detail.isNotEmpty ? e.detail : tr('Too many tries. Wait a minute and try again.')),
    _ when e.status >= 500 => DomainError(tr('HOLA is having a problem right now. Try again soon.')),
    _ => DomainError(e.detail.isEmpty ? tr('Something went wrong. Please try again.') : e.detail),
  };
}

/// "mainBranch.addressLine" → "Address line".
String _readable(String path) {
  final last = path.split('.').last.replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}');
  return last.isEmpty ? path : '${last[0].toUpperCase()}${last.substring(1)}';
}

DomainError _validation(ApiError e, Map<String, String> names) {
  if (e.fields.isEmpty) return DomainError(e.detail.isEmpty ? tr('Please check the details and try again.') : e.detail);
  final MapEntry(key: path, value: msg) = e.fields.entries.first;
  final field = names[path] ?? path;
  final text = switch (field) {
    'email' => tr('Enter a valid email address.'),
    // HOLA's words: too short, or too common (0.26.0); same code and path.
    'password' => msg.isEmpty ? tr('Use at least 8 characters for the password.') : tr(msg),
    'phone' => tr('Enter a valid phone number.'),
    'name' => tr('Enter your full name.'),
    // Name the field so the message makes sense outside a form.
    _ => '${_readable(path)}: $msg',
  };
  return DomainError(text, field: field);
}
