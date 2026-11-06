import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves the on-device run's screenshots and report on the Mac.
/// Folder: SHOTS env var, else build/device_sweep.
Future<void> main() {
  final dir = Platform.environment['SHOTS'] ?? 'build/device_sweep';
  return integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      File('$dir/$name.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      // Screens captured inside the app arrive as base64 PNGs.
      final images = (data?.remove('images') as Map?) ?? const {};
      for (final MapEntry(:key, :value) in images.entries) {
        File('$dir/$key.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(base64Decode(value as String));
      }
      File('$dir/report.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    },
  );
}
