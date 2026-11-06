import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/ui.dart';
import 'salon_cards.dart';

/// Salons' branches on an OpenStreetMap map, with the customer's own spot when
/// known. Tapping a pin shows that salon's card, which opens its page.
class SalonMap extends StatelessWidget {
  const SalonMap({super.key, required this.pins, this.here, this.distanceTo});
  final List<(Salon, Branch)> pins;
  final GeoFix? here;
  final double? Function(Salon)? distanceTo;

  static LatLng _ll(GeoFix g) => LatLng(g.lat, g.lng);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final points = [for (final (_, b) in pins) _ll(b.location!), if (here != null) _ll(here!)];
    // Fit everything in view; a single point gets a street-level zoom.
    final options = points.length > 1
        ? MapOptions(
            initialCameraFit: CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(56), maxZoom: 15),
          )
        : MapOptions(initialCenter: points.isEmpty ? const LatLng(31.5204, 74.3587) : points.first, initialZoom: points.isEmpty ? 5 : 14);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.bg2),
        child: FlutterMap(
          options: options,
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.metaxperts.hola'),
            MarkerLayer(
              markers: [
                if (here != null)
                  Marker(
                    point: _ll(here!),
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F80FF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x662F80FF), blurRadius: 12, spreadRadius: 4)],
                      ),
                    ),
                  ),
                for (final (s, b) in pins)
                  Marker(
                    point: _ll(b.location!),
                    width: 46,
                    height: 54,
                    alignment: Alignment.topCenter,
                    child: Tap(
                      onTap: () => _show(context, s),
                      child: _Pin(name: s.name),
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [TextSourceAttribution('OpenStreetMap contributors', onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright'), mode: LaunchMode.externalApplication))],
            ),
          ],
        ),
      ),
    );
  }

  void _show(BuildContext context, Salon s) => showHSheet(
    context,
    (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SalonCard(s, km: distanceTo?.call(s)),
    ),
  );
}

/// A map pin with the salon's initials.
class _Pin extends StatelessWidget {
  const _Pin({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.take(2).map((w) => w[0].toUpperCase()).join();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: G.btn,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Color(0x552F80FF), blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: Text(
            initials,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        CustomPaint(size: const Size(12, 8), painter: _Tip()),
      ],
    );
  }
}

class _Tip extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFF15418F));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
