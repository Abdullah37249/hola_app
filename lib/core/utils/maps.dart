import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/geo.dart';

/// Opens Google Maps with turn-by-turn directions to a place.
///
/// With GPS ([at]) it starts navigation straight away in the Google Maps app;
/// without it, it opens HOLA's [link] (a Google Maps directions URL) or
/// searches the written [address]. Returns false when nothing could open it.
Future<bool> startNavigation({GeoFix? at, required String address, String? link}) async {
  if (at != null) {
    final nav = Uri.parse('google.navigation:q=${at.lat},${at.lng}&mode=d');
    try {
      if (await launchUrl(nav, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {}
  }
  final ready = link == null ? null : Uri.tryParse(link);
  if (ready != null && ready.scheme == 'https') {
    try {
      if (await launchUrl(ready, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {}
  }
  final dest = at != null ? '${at.lat},${at.lng}' : address;
  final web = Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': dest, 'travelmode': 'driving', 'dir_action': 'navigate'});
  try {
    return await launchUrl(web, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
