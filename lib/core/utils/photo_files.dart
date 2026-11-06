import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

/// Photos kept on the device, in a `photos` folder inside the app's private
/// files directory (the same place as the database). Records store only the
/// file name, because the directory path can change between app updates.
abstract final class PhotoFiles {
  static const _channel = MethodChannel('hola/storage');
  static String? _dir;

  /// Finds the photos folder. Without the platform channel (tests) photos are
  /// simply unavailable and screens fall back to the generated artwork.
  static Future<void> init() async {
    try {
      final base = await _channel.invokeMethod<String>('filesDir');
      if (base == null) return;
      final d = Directory('$base/photos');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d.path;
    } on MissingPluginException {
      _dir = null;
    }
  }

  static bool get available => _dir != null;

  /// The stored file for [name], or null if it isn't on this device.
  static File? file(String? name) {
    if (name == null || _dir == null) return null;
    final f = File('$_dir/$name');
    return f.existsSync() ? f : null;
  }

  /// Copies a picked image into the photos folder and returns its new name.
  static Future<String> keep(String sourcePath) async {
    if (_dir == null) throw StateError('Photo storage is not available.');
    final name = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32).toRadixString(36)}.jpg';
    await File(sourcePath).copy('$_dir/$name');
    return name;
  }

  /// Saves downloaded bytes under [name] (e.g. a chat photo from HOLA).
  static Future<File?> write(String name, List<int> bytes) async {
    if (_dir == null) return null;
    final f = File('$_dir/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static Future<void> delete(String name) async {
    final f = file(name);
    if (f != null) await f.delete();
  }
}
