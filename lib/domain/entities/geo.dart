import 'dart:math' as math;

import 'json.dart';

/// A GPS reading: where something happened, and how sure the phone was.
class GeoFix {
  final double lat, lng;

  /// Radius in metres the phone is confident about.
  final double accuracy;
  const GeoFix(this.lat, this.lng, {this.accuracy = 0});

  Json toJson() => {'lat': lat, 'lng': lng, 'accuracy': accuracy};
  static GeoFix? fromJson(Object? j) => j is Map ? GeoFix(asDouble(j['lat']), asDouble(j['lng']), accuracy: asDouble(j['accuracy'])) : null;

  /// "31.52040, 74.35870 (±12 m)".
  String get label => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}${accuracy > 0 ? ' (±${accuracy.round()} m)' : ''}';
}

/// Straight-line distance between two points, in kilometres (haversine).
double distanceKm(GeoFix a, GeoFix b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}
