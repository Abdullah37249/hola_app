import 'package:flutter/material.dart';

/// HOLA design tokens (DESIGN_SYSTEM v0.1.1 + prototype v2 uplift).
/// Read them in widgets through `context.c` (light/dark aware).
@immutable
class HolaColors extends ThemeExtension<HolaColors> {
  final Color brand, onBrand, brandText, brandSoft, brandLine;
  final Color ink, body, muted, subtle;
  final Color bg, bg2, surface, surface2, line;
  final Color accent, accentSoft, accentInk;
  final Color ok, okSoft, bad, badSoft, badInk;
  final Color night, wine, glass, scrim;
  final Color mapRoad, mapPark, mapWater;
  final List<BoxShadow> lift, liftHi;
  final bool dark;

  const HolaColors({
    required this.brand,
    required this.onBrand,
    required this.brandText,
    required this.brandSoft,
    required this.brandLine,
    required this.ink,
    required this.body,
    required this.muted,
    required this.subtle,
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
    required this.ok,
    required this.okSoft,
    required this.bad,
    required this.badSoft,
    required this.badInk,
    required this.night,
    required this.wine,
    required this.glass,
    required this.scrim,
    required this.mapRoad,
    required this.mapPark,
    required this.mapWater,
    required this.lift,
    required this.liftHi,
    required this.dark,
  });

  /// Light: cool white pages under the same glowing night header.
  static const light = HolaColors(
    // The header's royal blue, 5% lighter (owner, 2 Nov 2026).
    brand: Color(0xFF144693),
    onBrand: Colors.white,
    brandText: Color(0xFF144693),
    brandSoft: Color(0xFFE7EDF6),
    brandLine: Color(0xFFC3D0E6),
    ink: Color(0xFF0A1020),
    body: Color(0xFF2E3747),
    muted: Color(0xFF66708A),
    subtle: Color(0xFF9AA3B8),
    bg: Color(0xFFF3F6FC),
    bg2: Color(0xFFE7EDF7),
    surface: Colors.white,
    surface2: Color(0xFFF7F9FD),
    line: Color(0xFFDDE5F1),
    accent: Color(0xFFFF8A00),
    accentSoft: Color(0xFFFFF1E0),
    accentInk: Color(0xFF9A4F00),
    ok: Color(0xFF14854E),
    okSoft: Color(0xFFE3F2EA),
    bad: Color(0xFFE5243B),
    badSoft: Color(0xFFFDE8EA),
    badInk: Color(0xFFC4142A),
    night: Color(0xFF02050C),
    wine: Color(0xFF771913),
    glass: Color(0xD9FFFFFF),
    scrim: Color(0x7302050C),
    mapRoad: Colors.white,
    mapPark: Color(0xFFDCE8DA),
    mapWater: Color(0xFFCFE0F5),
    lift: [
      BoxShadow(color: Color(0x0A0A1A3A), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x1A1659D6), blurRadius: 26, spreadRadius: -10, offset: Offset(0, 10)),
    ],
    liftHi: [
      BoxShadow(color: Color(0x0D0A1A3A), blurRadius: 4, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x331659D6), blurRadius: 38, spreadRadius: -12, offset: Offset(0, 16)),
    ],
    dark: false,
  );

  /// Default look, after the HOLA Circle poster: near-black navy, electric
  /// blue glow, white type.
  static const darkTheme = HolaColors(
    // Same header blue; a touch brighter so it reads on black.
    brand: Color(0xFF2A5FB8),
    onBrand: Colors.white,
    brandText: Color(0xFFA9C2EC),
    brandSoft: Color(0xFF0D1C38),
    brandLine: Color(0xFF1F3F78),
    ink: Color(0xFFF5F8FF),
    body: Color(0xFFD3DCEB),
    muted: Color(0xFF8D9AB3),
    subtle: Color(0xFF56647E),
    bg: Color(0xFF02050C),
    bg2: Color(0xFF081022),
    surface: Color(0xFF0A1428),
    surface2: Color(0xFF0F1B34),
    line: Color(0xFF1A2A4A),
    accent: Color(0xFFFF8A00),
    accentSoft: Color(0xFF2A1A08),
    accentInk: Color(0xFFFFB15C),
    ok: Color(0xFF3DD68C),
    okSoft: Color(0xFF0B2A1D),
    bad: Color(0xFFFF5C6C),
    badSoft: Color(0xFF2E0F17),
    badInk: Color(0xFFFF8A96),
    night: Color(0xFF02050C),
    wine: Color(0xFF771913),
    glass: Color(0xCC081022),
    scrim: Color(0x99000000),
    mapRoad: Color(0xFF1A2A4A),
    mapPark: Color(0xFF0E2420),
    mapWater: Color(0xFF0D1E3D),
    lift: [
      BoxShadow(color: Color(0x80000000), blurRadius: 24, spreadRadius: -8, offset: Offset(0, 10)),
      BoxShadow(color: Color(0x162F80FF), blurRadius: 28, spreadRadius: -6),
    ],
    liftHi: [
      BoxShadow(color: Color(0x99000000), blurRadius: 36, spreadRadius: -12, offset: Offset(0, 16)),
      BoxShadow(color: Color(0x332F80FF), blurRadius: 40, spreadRadius: -8),
    ],
    dark: true,
  );

  @override
  HolaColors copyWith() => this;

  @override
  HolaColors lerp(ThemeExtension<HolaColors>? other, double t) => (other is HolaColors && t > .5) ? other : this;
}

extension HolaCtx on BuildContext {
  HolaColors get c => Theme.of(this).extension<HolaColors>()!;
}

/// Brand gradients, after the HOLA Circle poster: electric blue light on night.
class G {
  /// Buttons: the header's blue, 5% lighter.
  static const btn = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF144693), Color(0xFF123871)]);

  /// Feature tile (hero cards): night to deep blue.
  static const sun = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF040A18), Color(0xFF0A2457), Color(0xFF1546A8)], stops: [0, .6, 1]);

  /// Headline highlight (top KPI, seals, progress): luminous blue.
  static const flame = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E55A8), Color(0xFF123871)]);

  /// HOLA orange, for the few places that must stand apart from the blue.
  static const orange = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF9F2E), Color(0xFFE86F00)]);
  static const ok = LinearGradient(colors: [Color(0xFF22A866), Color(0xFF14854E)]);
  static const danger = LinearGradient(colors: [Color(0xFFFF4D5E), Color(0xFFD1142B)]);
  static const credit = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF02050C), Color(0xFF0A2457), Color(0xFF144693)], stops: [0, .55, 1]);
  static const progress = LinearGradient(colors: [Color(0xFF7FA3D9), Color(0xFF144693), Color(0xFF123871)], stops: [0, .55, 1]);

  /// Header: the poster's night sky. The role only tints the glow a little.
  static (LinearGradient, Color, Color) band(String role) {
    const base = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF000000), Color(0xFF020814), Color(0xFF041230)], stops: [0, .5, 1]);
    final glow = switch (role) {
      'salon' => const Color(0xFF4F7BFF), // indigo blue
      'rider' => const Color(0xFF3FA9FF), // sky
      'field' => const Color(0xFF2F80FF),
      _ => const Color(0xFF2F80FF),
    };
    return (base, glow, glow);
  }

  /// Category tile gradients (8 cool tones, cycled).
  static const cats = [
    [Color(0xFF2F80FF), Color(0xFF1546A8)], // electric
    [Color(0xFF5B5BD6), Color(0xFF3A3AA0)], // indigo
    [Color(0xFF1FA2C8), Color(0xFF136F8C)], // cyan
    [Color(0xFF7A5BE0), Color(0xFF5038A8)], // violet
    [Color(0xFF2C6BB8), Color(0xFF1A4478)], // sapphire
    [Color(0xFF3D4A66), Color(0xFF232B3D)], // steel
    [Color(0xFF169C8F), Color(0xFF0F6B62)], // teal
    [Color(0xFF4A90E2), Color(0xFF2A62A8)], // azure
  ];
}

/// Type scale: Montserrat headings (wide and geometric, like the HOLA
/// wordmark), Instrument Sans for reading text.
class T {
  static const f = 'InstrumentSans';
  static const head = 'Montserrat';
  static TextStyle display(BuildContext c) => TextStyle(fontFamily: head, fontSize: 30, height: 38 / 30, fontWeight: FontWeight.w600, letterSpacing: -.6, color: c.c.ink);
  static TextStyle h1(BuildContext c) => TextStyle(fontFamily: head, fontSize: 26, height: 34 / 26, fontWeight: FontWeight.w600, letterSpacing: -.5, color: c.c.ink);
  static TextStyle h2(BuildContext c) => TextStyle(fontFamily: head, fontSize: 19, height: 26 / 19, fontWeight: FontWeight.w600, letterSpacing: -.3, color: c.c.ink);
  static TextStyle h3(BuildContext c) => TextStyle(fontFamily: head, fontSize: 16, height: 23 / 16, fontWeight: FontWeight.w600, letterSpacing: -.2, color: c.c.ink);
  static TextStyle body(BuildContext c) => TextStyle(fontFamily: f, fontSize: 16, height: 26 / 16, fontWeight: FontWeight.w500, color: c.c.body);
  static TextStyle sm(BuildContext c) => TextStyle(fontFamily: f, fontSize: 14, height: 22 / 14, fontWeight: FontWeight.w500, color: c.c.body);
  static TextStyle cap(BuildContext c) => TextStyle(fontFamily: f, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: c.c.muted);
  static TextStyle eyebrow(BuildContext c) => TextStyle(fontFamily: head, fontSize: 10.5, height: 16 / 10.5, fontWeight: FontWeight.w600, letterSpacing: 2.4, color: c.c.muted);
  static TextStyle ttl(BuildContext c) => TextStyle(fontFamily: f, fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600, color: c.c.ink);
  static TextStyle sub(BuildContext c) => TextStyle(fontFamily: f, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: c.c.muted);
  static TextStyle link(BuildContext c) => TextStyle(fontFamily: f, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: c.c.brandText);
}

const kGutter = 16.0;
const kSpring = Cubic(.3, 1.4, .5, 1);
const kEase = Cubic(.2, 0, 0, 1);

ThemeData buildTheme(bool dark) {
  final hc = dark ? HolaColors.darkTheme : HolaColors.light;
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    fontFamily: T.f,
    scaffoldBackgroundColor: hc.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF144693), brightness: dark ? Brightness.dark : Brightness.light, primary: hc.brand, surface: hc.surface),
    splashFactory: InkSparkle.splashFactory,
    extensions: [hc],
    textSelectionTheme: TextSelectionThemeData(cursorColor: hc.brand),
  );
}
