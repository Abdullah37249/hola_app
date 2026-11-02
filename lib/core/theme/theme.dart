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

  static const light = HolaColors(
    brand: Color(0xFF005BAC),
    onBrand: Colors.white,
    brandText: Color(0xFF005BAC),
    brandSoft: Color(0xFFEBF2FA),
    brandLine: Color(0xFFC7DAEE),
    ink: Color(0xFF15151A),
    body: Color(0xFF3F3E45),
    muted: Color(0xFF6F6C74),
    subtle: Color(0xFFA29EA7),
    bg: Color(0xFFF7F4EE),
    bg2: Color(0xFFEFEBE3),
    surface: Colors.white,
    surface2: Color(0xFFFAF8F4),
    line: Color(0xFFEAE5DC),
    accent: Color(0xFFFF8A00),
    accentSoft: Color(0xFFFFF1E0),
    accentInk: Color(0xFF9A4F00),
    ok: Color(0xFF14854E),
    okSoft: Color(0xFFE3F2EA),
    bad: Color(0xFFF61F1F),
    badSoft: Color(0xFFFDE8E8),
    badInk: Color(0xFFC41414),
    night: Color(0xFF13111C),
    wine: Color(0xFF771913),
    glass: Color(0xD1FFFFFF),
    scrim: Color(0x6B13111C),
    mapRoad: Colors.white,
    mapPark: Color(0xFFDDE8D3),
    mapWater: Color(0xFFCFE0F2),
    lift: [
      BoxShadow(color: Color(0x0A1C1A14), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x141C1A14), blurRadius: 24, spreadRadius: -8, offset: Offset(0, 8)),
    ],
    liftHi: [
      BoxShadow(color: Color(0x0D1C1A14), blurRadius: 4, offset: Offset(0, 2)),
      BoxShadow(color: Color(0x241C1A14), blurRadius: 36, spreadRadius: -12, offset: Offset(0, 16)),
    ],
    dark: false,
  );

  static const darkTheme = HolaColors(
    brand: Color(0xFF1A6CC0),
    onBrand: Colors.white,
    brandText: Color(0xFF7DB6EE),
    brandSoft: Color(0xFF16233A),
    brandLine: Color(0xFF28466E),
    ink: Color(0xFFF2EFE6),
    body: Color(0xFFD4D0C6),
    muted: Color(0xFFA39F96),
    subtle: Color(0xFF6E6A78),
    bg: Color(0xFF13111C),
    bg2: Color(0xFF1A1825),
    surface: Color(0xFF1E1C29),
    surface2: Color(0xFF252332),
    line: Color(0xFF2F2C3D),
    accent: Color(0xFFFF8A00),
    accentSoft: Color(0xFF33230F),
    accentInk: Color(0xFFFFB15C),
    ok: Color(0xFF3DBE7C),
    okSoft: Color(0xFF10291C),
    bad: Color(0xFFFF5C5C),
    badSoft: Color(0xFF3A1518),
    badInk: Color(0xFFFF8A8A),
    night: Color(0xFF13111C),
    wine: Color(0xFF771913),
    glass: Color(0xD11E1C29),
    scrim: Color(0x8C000000),
    mapRoad: Color(0xFF2C2A3A),
    mapPark: Color(0xFF1C2A22),
    mapWater: Color(0xFF16233A),
    lift: [
      BoxShadow(color: Color(0x4D000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x99000000), blurRadius: 28, spreadRadius: -10, offset: Offset(0, 10)),
    ],
    liftHi: [
      BoxShadow(color: Color(0xB3000000), blurRadius: 40, spreadRadius: -12, offset: Offset(0, 18)),
    ],
    dark: true,
  );

  @override
  HolaColors copyWith() => this;

  @override
  HolaColors lerp(ThemeExtension<HolaColors>? other, double t) =>
      (other is HolaColors && t > .5) ? other : this;
}

extension HolaCtx on BuildContext {
  HolaColors get c => Theme.of(this).extension<HolaColors>()!;
}

/// Brand gradients from prototype v2.
class G {
  static const btn = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0A68BF), Color(0xFF00529C)]);
  /// Highlight tile (KPIs, featured cards): deep ink-to-brand.
  static const sun = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0E2747), Color(0xFF0A4F94)]);
  /// Headline KPI on a brand band: HOLA orange so it stands apart from the blue.
  static const flame = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF9F2E), Color(0xFFE86F00)]);
  static const ok = LinearGradient(colors: [Color(0xFF22A866), Color(0xFF14854E)]);
  static const danger = LinearGradient(colors: [Color(0xFFFF4D4D), Color(0xFFD11414)]);
  static const credit = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF13111C), Color(0xFF0B2F5C), Color(0xFF005BAC)],
    stops: [0, .55, 1],
  );
  static const progress = LinearGradient(
    colors: [Color(0xFF2588E8), Color(0xFF005BAC), Color(0xFFFF8A00)],
    stops: [0, .6, 1],
  );

  /// Header band: one calm, premium navy for every experience. The role only
  /// shifts the soft highlight so each experience has a hint of its own.
  static (LinearGradient, Color, Color) band(String role) {
    const base = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B1B33), Color(0xFF0B3566), Color(0xFF0A4F94)], stops: [0, .55, 1]);
    final glow = switch (role) {
      'salon' || 'sstaff' => const Color(0x33E8B98A), // champagne
      'rider' => const Color(0x33FFC27A),
      _ => const Color(0x335E9BD6),
    };
    return (base, glow, glow);
  }

  /// Category tile gradients (8 colours, cycled).
  /// Muted jewel tones, harmonised (category tiles, quick actions).
  static const cats = [
    [Color(0xFF2F6FB0), Color(0xFF1C4F86)], // sapphire
    [Color(0xFF9A4A3F), Color(0xFF6E2C25)], // garnet
    [Color(0xFFC08A3E), Color(0xFF94652A)], // ochre
    [Color(0xFF4F8A6E), Color(0xFF316650)], // sage
    [Color(0xFF7A6496), Color(0xFF574572)], // plum
    [Color(0xFF4A4756), Color(0xFF2B2935)], // graphite
    [Color(0xFF3F8C93), Color(0xFF2A6A70)], // teal
    [Color(0xFFB3694C), Color(0xFF8A4A33)], // terracotta
  ];
}

/// Type scale (Instrument Sans; body 500, headings 600).
class T {
  static const f = 'InstrumentSans';
  /// Display serif for page titles and hero numbers.
  static const serif = 'DMSerifDisplay';
  static TextStyle display(BuildContext c) => TextStyle(fontFamily: serif, fontSize: 34, height: 40 / 34, fontWeight: FontWeight.w400, letterSpacing: -.3, color: c.c.ink);
  static TextStyle h1(BuildContext c) => TextStyle(fontFamily: serif, fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w400, letterSpacing: -.2, color: c.c.ink);
  static TextStyle h2(BuildContext c) => TextStyle(fontFamily: f, fontSize: 21, height: 28 / 21, fontWeight: FontWeight.w600, letterSpacing: -.3, color: c.c.ink);
  static TextStyle h3(BuildContext c) => TextStyle(fontFamily: f, fontSize: 17, height: 24 / 17, fontWeight: FontWeight.w600, letterSpacing: -.15, color: c.c.ink);
  static TextStyle body(BuildContext c) => TextStyle(fontFamily: f, fontSize: 16, height: 26 / 16, fontWeight: FontWeight.w500, color: c.c.body);
  static TextStyle sm(BuildContext c) => TextStyle(fontFamily: f, fontSize: 14, height: 22 / 14, fontWeight: FontWeight.w500, color: c.c.body);
  static TextStyle cap(BuildContext c) => TextStyle(fontFamily: f, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: c.c.muted);
  static TextStyle eyebrow(BuildContext c) => TextStyle(fontFamily: f, fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w600, letterSpacing: 1.6, color: c.c.muted);
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
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005BAC), brightness: dark ? Brightness.dark : Brightness.light, primary: hc.brand, surface: hc.surface),
    splashFactory: InkSparkle.splashFactory,
    extensions: [hc],
    textSelectionTheme: TextSelectionThemeData(cursorColor: hc.brand),
  );
}
