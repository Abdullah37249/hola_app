import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/entities/entities.dart';

/// Which accounts have fingerprint sign-in on this phone (each on its own),
/// and who has already been asked about it. Kept in encrypted storage.
abstract class FingerprintStore {
  Future<List<FingerprintAccount>> read();
  Future<void> write(List<FingerprintAccount> all);
  Future<Set<String>> offered();
  Future<void> addOffered(String accountId);
}

class SecureFingerprintStore implements FingerprintStore {
  static const _key = 'hola.fingerprints', _legacy = 'hola.fingerprint', _asked = 'hola.fingerprint.asked';
  final _s = const FlutterSecureStorage();

  @override
  Future<List<FingerprintAccount>> read() async {
    try {
      // Earlier builds kept a single account.
      final old = await _s.read(key: _legacy);
      if (old != null) {
        final one = FingerprintAccount.fromJson(jsonDecode(old) as Map<String, dynamic>);
        final all = [...await _list().then((l) => l.where((a) => a.accountId != one.accountId)), one];
        await write(all);
        await _s.delete(key: _legacy);
        return all;
      }
      return await _list();
    } catch (_) {
      return [];
    }
  }

  Future<List<FingerprintAccount>> _list() async {
    final v = await _s.read(key: _key);
    return v == null ? [] : [for (final j in jsonDecode(v) as List) FingerprintAccount.fromJson((j as Map).cast<String, dynamic>())];
  }

  @override
  Future<void> write(List<FingerprintAccount> all) async {
    try {
      all.isEmpty ? await _s.delete(key: _key) : await _s.write(key: _key, value: jsonEncode([for (final a in all) a.toJson()]));
    } catch (_) {}
  }

  @override
  Future<Set<String>> offered() async {
    try {
      final v = await _s.read(key: _asked);
      return v == null ? {} : {for (final x in jsonDecode(v) as List) '$x'};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> addOffered(String accountId) async {
    final all = await offered()
      ..add(accountId);
    try {
      await _s.write(key: _asked, value: jsonEncode(all.toList()));
    } catch (_) {}
  }
}

class MemoryFingerprintStore implements FingerprintStore {
  List<FingerprintAccount> all = [];
  final asked = <String>{};
  @override
  Future<List<FingerprintAccount>> read() async => [...all];
  @override
  Future<void> write(List<FingerprintAccount> v) async => all = [...v];
  @override
  Future<Set<String>> offered() async => {...asked};
  @override
  Future<void> addOffered(String accountId) async => asked.add(accountId);
}
