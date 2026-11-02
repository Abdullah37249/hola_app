import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Where the database JSON lives. Swappable so tests run in memory.
abstract interface class Storage {
  Future<String?> read();
  Future<void> write(String data);
}

/// App-private file (`filesDir` on Android, Application Support on iOS),
/// written atomically via a temp file + rename.
class FileStorage implements Storage {
  static const _channel = MethodChannel('hola/storage');
  File? _file;

  Future<File> _target() async {
    if (_file != null) return _file!;
    final dir = await _channel.invokeMethod<String>('filesDir');
    return _file = File('$dir/hola_db.json');
  }

  @override
  Future<String?> read() async {
    final f = await _target();
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String data) async {
    final f = await _target();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }
}

class MemoryStorage implements Storage {
  String? data;
  MemoryStorage([this.data]);
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String d) async => data = d;
}

String encodeJson(Object o) => jsonEncode(o);
Object? decodeJson(String s) => jsonDecode(s);
