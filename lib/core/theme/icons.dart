// Icon set ported 1:1 from the prototype (24×24, stroke).
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const Map<String, String> _paths = {
  'home': r'''M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z''',
  'search': r'''<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>''',
  'cal': r'''<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>''',
  'bag': r'''<path d="M5 8h14l-1 13H6z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/>''',
  'user': r'''<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>''',
  'bell': r'''<path d="M6 16v-5a6 6 0 1 1 12 0v5l2 2H4z"/><path d="M10 21h4"/>''',
  'back': r'''m15 18-6-6 6-6''',
  'chev': r'''m9 18 6-6-6-6''',
  'down': r'''m6 9 6 6 6-6''',
  'star': r'''m12 3 2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3l-5.5 2.9 1-6.2L3 9.6l6.2-.9z''',
  'pin': r'''<path d="M12 21s-7-6.2-7-12a7 7 0 0 1 14 0c0 5.8-7 12-7 12z"/><circle cx="12" cy="9" r="2.5"/>''',
  'clock': r'''<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>''',
  'scissors': r'''<circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M8.6 7.6 20 18M8.6 16.4 20 6"/>''',
  'check': r'''m5 12.5 4.5 4.5L19 7.5''',
  'x': r'''M6 6l12 12M18 6 6 18''',
  'plus': r'''M12 5v14M5 12h14''',
  'minus': r'''M5 12h14''',
  'filter': r'''M4 6h16M7 12h10M10 18h4''',
  'heart': r'''M12 20s-8-4.6-8-10.5A4.5 4.5 0 0 1 12 7a4.5 4.5 0 0 1 8 2.5C20 15.4 12 20 12 20z''',
  'truck': r'''<path d="M2 6h12v10H2zM14 10h4l3 3v3h-7"/><circle cx="6" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>''',
  'box': r'''<path d="M3 7.5 12 3l9 4.5v9L12 21l-9-4.5z"/><path d="M3 7.5 12 12l9-4.5M12 12v9"/>''',
  'users': r'''<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6 6 0 0 1 3.5 6"/>''',
  'clip': r'''<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4h6v3H9zM9 12h6M9 16h4"/>''',
  'camera': r'''<path d="M4 8h3l2-3h6l2 3h3v12H4z"/><circle cx="12" cy="13.5" r="3.5"/>''',
  'wifi': r'''<path d="M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19" r=".8"/>''',
  'wifiOff': r'''<path d="M2 9a15 15 0 0 1 20 0M5 12.5a10 10 0 0 1 14 0M8.5 16a5 5 0 0 1 7 0M3 3l18 18"/>''',
  'sync': r'''<path d="M20 11a8 8 0 0 0-14.7-4M4 13a8 8 0 0 0 14.7 4"/><path d="M5 3v4h4M19 21v-4h-4"/>''',
  'chart': r'''M4 20V10M10 20V4M16 20v-7M22 20H2''',
  'grad': r'''<path d="m2 9 10-5 10 5-10 5z"/><path d="M6 11v5c3 2.5 9 2.5 12 0v-5"/>''',
  'award': r'''<circle cx="12" cy="9" r="6"/><path d="m8.6 13.9-1.6 7.1 5-2.6 5 2.6-1.6-7.1"/>''',
  'store': r'''<path d="M4 9 5.5 4h13L20 9M4 9h16v11H4zM4 9a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0 2.7 2.7 0 0 0 5.3 0M10 20v-5h4v5"/>''',
  'nav': r'''m3 11 18-8-8 18-2-8z''',
  'file': r'''<path d="M6 3h8l5 5v13H6z"/><path d="M14 3v5h5"/>''',
  'logout': r'''M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10''',
  'grid':
      r'''<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>''',
  'map': r'''<path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>''',
  'list': r'''M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01''',
  'sparkle': r'''M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M18 6l-2.5 2.5M8.5 15.5 6 18''',
  'msg': r'''M4 5h16v11H9l-5 4z''',
  'mail': r'''<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3.5 6.5 8.5 6.5 8.5-6.5"/>''',
  'phone': r'''M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a1 1 0 0 1-1 1A16 16 0 0 1 4 5a1 1 0 0 1 1-1z''',
  'shield': r'''<path d="M12 3 5 6v6c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6z"/><path d="m9 12 2 2 4-4"/>''',
  'edit': r'''M4 20h4L19 9l-4-4L4 16z''',
  'cash': r'''<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 12h.01M18 12h.01"/>''',
  'upload': r'''M12 16V4M7 9l5-5 5 5M4 20h16''',
  'ext': r'''M14 4h6v6M20 4l-9 9M18 14v6H4V6h6''',
  'drop': r'''M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z''',
  'hand':
      r'''<path d="M7 11V6a1.5 1.5 0 0 1 3 0v5M10 10V4.5a1.5 1.5 0 0 1 3 0V10M13 10V5.5a1.5 1.5 0 0 1 3 0V12M16 9a1.5 1.5 0 0 1 3 0v4a7 7 0 0 1-7 7h-1a6 6 0 0 1-5-2.7L3.5 14a1.5 1.5 0 0 1 2.4-1.8L7 13.5"/>''',
  'sun': r'''<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.4 1.4M17.6 17.6 19 19M5 19l1.4-1.4M17.6 6.4 19 5"/>''',
  'vol': r'''<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M16.5 8.5a5 5 0 0 1 0 7"/>''',
  'layers': r'''<path d="m12 3 9 5-9 5-9-5z"/><path d="m3 13 9 5 9-5"/>''',
  'doc': r'''<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 8h6M9 12h6M9 16h3"/>''',
  'alert': r'''<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17h.01"/>''',
  'route': r'''<circle cx="6" cy="19" r="2"/><circle cx="18" cy="5" r="2"/><path d="M8 19h8a3.5 3.5 0 0 0 0-7H8a3.5 3.5 0 0 1 0-7h8"/>''',
  'color':
      r'''<circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 0 0 18c1.5 0 2-1 2-2s-1-1.5-1-2.5 1-1.5 2-1.5h2a4 4 0 0 0 4-4c0-4.4-4-8-9-8z"/><circle cx="7.5" cy="11" r="1"/><circle cx="10" cy="7" r="1"/><circle cx="15" cy="7.5" r="1"/>''',
};

/// HOLA stroke icon. [fill] fills shapes (e.g. star, heart).
class HIcon extends StatelessWidget {
  final String name;
  final double size;
  final double stroke;
  final Color? color;
  final bool fill;
  const HIcon(this.name, {super.key, this.size = 22, this.stroke = 1.8, this.color, this.fill = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    final p = _paths[name] ?? '';
    final body = p.startsWith('<') ? p : '<path d="$p"/>';
    final hex = '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="${fill ? hex : 'none'}" stroke="$hex" stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round">$body</svg>';
    final icon = Opacity(
      opacity: c.a,
      child: SvgPicture.string(svg, width: size, height: size),
    );
    // Directional arrows point the other way in right-to-left (Urdu).
    return _directional.contains(name) && Directionality.maybeOf(context) == TextDirection.rtl ? Transform.flip(flipX: true, child: icon) : icon;
  }

  static const _directional = {'back', 'chev', 'nav', 'ext'};
}
