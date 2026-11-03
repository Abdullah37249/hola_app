import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/entities/geo.dart';

/// Reads the phone's GPS once. Returns null (never a guess) when location is
/// off, permission is refused, or no fix arrives in time.
class Location {
  /// Swappable in tests.
  static Future<GeoFix?> Function() read = _read;

  static Future<GeoFix?> _read() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return GeoFix(pos.latitude, pos.longitude, accuracy: pos.accuracy);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null; // timeout or no fix
    }
  }
}
