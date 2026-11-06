import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:hola_professional/core/theme/icons.dart';
import 'package:hola_professional/core/utils/sfx.dart';
import 'package:hola_professional/core/theme/theme.dart';
import 'states.dart';
import 'ui.dart' show InPage, HButton, BtnKind, T, tr;

/// Global effects host: the "dynamic island" toast and brand confetti.
/// Mounted once above the navigator (see `FxHost`).
class Fx {
  static final _toast = ValueNotifier<_ToastData?>(null);
  static final _confetti = ValueNotifier<int>(0);
  static Timer? _t;

  /// tone: '' (ok) | 'bad' | 'info' | 'warn'
  static void toast(String msg, {String icon = 'check', String tone = ''}) {
    _toast.value = _ToastData(msg, icon, tone, DateTime.now().microsecondsSinceEpoch);
    _t?.cancel();
    // Longer messages stay a little longer so they can be read (or tapped).
    _t = Timer(Duration(milliseconds: msg.length > 60 ? 4200 : 2600), () => _toast.value = null);
  }

  /// The app's navigator, so a tapped toast (drawn above it) can open the
  /// full message.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// A cut-off toast was tapped: hide it and show all of it.
  static void _expand(_ToastData d) {
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) return;
    _t?.cancel();
    _toast.value = null;
    Sfx.tap();
    showFullMessage(ctx, message: d.msg, icon: d.icon, tone: d.tone);
  }

  static void confetti() => _confetti.value++;
}

/// The whole text of a message that was cut off (a toast or a notification),
/// in a small popup. [action] adds a second button (e.g. "Open").
Future<void> showFullMessage(BuildContext context, {String title = '', required String message, String icon = 'bell', String tone = 'info', (String, VoidCallback)? action}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Close'),
    barrierColor: const Color(0x8C000000),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (_, a, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(begin: .94, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
    pageBuilder: (ctx, _, __) {
      final c = ctx.c;
      final ib = switch (tone) {
        'bad' => c.bad,
        'warn' => c.accent,
        'ok' || '' => c.ok,
        _ => c.brand,
      };
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Material(
              color: c.surface,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 420, maxHeight: MediaQuery.sizeOf(ctx).height * .7),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: ib, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: HIcon(icon, size: 19, stroke: 2.2, color: Colors.white),
                          ),
                          if (title.isNotEmpty) ...[const SizedBox(width: 12), Expanded(child: Text(title, style: T.ttl(ctx)))],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Flexible(
                        child: SingleChildScrollView(
                          child: SelectableText(message, style: T.body(ctx).copyWith(color: c.ink)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (action != null) ...[
                        HButton(
                          action.$1,
                          block: true,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            action.$2();
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                      HButton(tr('Close'), kind: action == null ? BtnKind.primary : BtnKind.ghost, block: true, onTap: () => Navigator.of(ctx).pop()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ToastData {
  final String msg, icon, tone;
  final int k;
  _ToastData(this.msg, this.icon, this.tone, this.k);
}

/// Push a page with the prototype's slide-in + parallax transition and nav sound.
/// Lets go of the text field being typed in, so coming back to this screen
/// doesn't pop the keyboard up again on its own.
void dropFocus() => FocusManager.instance.primaryFocus?.unfocus();

Future<R?> pushPage<R>(BuildContext context, Widget page) {
  Sfx.nav();
  dropFocus();
  return Navigator.of(context).push<R>(HolaRoute(page));
}

/// Opens a tab screen (e.g. Team) as its own page, with a back button.
Future<R?> pushTab<R>(BuildContext context, Widget tab) {
  Sfx.nav();
  dropFocus();
  return Navigator.of(context).push<R>(
    HolaRoute(
      Builder(
        builder: (c) => Scaffold(
          backgroundColor: c.c.bg,
          body: InPage(child: tab),
        ),
      ),
    ),
  );
}

/// Replace the top page (e.g. booking → booked confirmation).
Future<R?> replacePage<R>(BuildContext context, Widget page) {
  Sfx.nav();
  return Navigator.of(context).pushReplacement(HolaRoute(page));
}

void popPage(BuildContext context) {
  Sfx.back();
  Navigator.of(context).maybePop();
}

class HolaRoute<R> extends PageRouteBuilder<R> {
  HolaRoute(Widget page)
    : super(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (context, a, s, child) {
          final inC = CurvedAnimation(parent: a, curve: kEase, reverseCurve: kEase.flipped);
          final under = CurvedAnimation(parent: s, curve: kEase);
          // New pages come in from the reading-end side: right in English, left in Urdu.
          final d = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
          return SlideTransition(
            position: Tween(begin: Offset.zero, end: Offset(-.24 * d, 0)).animate(under),
            child: SlideTransition(
              position: Tween(begin: Offset(d, 0), end: Offset.zero).animate(inC),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(color: const Color(0x1A13111C), blurRadius: 32, offset: Offset(-12 * d, 0))],
                ),
                child: child,
              ),
            ),
          );
        },
      );

  // Allow the iOS-style edge swipe back on Android too (prototype edge swipe).
  @override
  bool get popGestureEnabled => true;
}

class FxHost extends StatelessWidget {
  final Widget child;
  const FxHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<int>(
              valueListenable: Fx._confetti,
              builder: (_, v, __) => v == 0 ? const SizedBox() : _Confetti(key: ValueKey(v)),
            ),
          ),
        ),
        Positioned(top: top + 8, left: 16, right: 16, child: const OfflineBanner()),
        Positioned(
          top: top + 8,
          left: 0,
          right: 0,
          child: Center(
            child: ValueListenableBuilder<_ToastData?>(
              valueListenable: Fx._toast,
              // Only a showing toast takes taps; the screen below stays usable.
              builder: (context, d, _) => IgnorePointer(
                ignoring: d == null,
                child: _Island(data: d),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Island extends StatelessWidget {
  final _ToastData? data;
  const _Island({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final show = data != null;
    final w = math.min(330.0, MediaQuery.sizeOf(context).width - 32);
    final tone = data?.tone ?? '';
    // Does the message fit the island's two lines? If not, a tap shows it all.
    const style = TextStyle(fontFamily: T.f, color: Colors.white, fontSize: 14, height: 18 / 14, fontWeight: FontWeight.w600, decoration: TextDecoration.none);
    final cut =
        data != null &&
        (TextPainter(
          text: TextSpan(text: data!.msg, style: style),
          maxLines: 2,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: w - 28 - 38 - 22)).didExceedMaxLines;
    final ib = tone == 'bad'
        ? c.bad
        : tone == 'info'
        ? c.brand
        : tone == 'warn'
        ? c.accent
        : c.ok;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: cut ? () => Fx._expand(data!) : null,
      child: Semantics(
        button: cut,
        hint: cut ? tr('Tap to read the full message') : null,
        child: AnimatedContainer(
          duration: Duration(milliseconds: show ? 420 : 260),
          // Spring in, ease out: an overshooting curve would collapse past zero size.
          curve: show ? kSpring : Curves.easeInCubic,
          width: show ? w : 0,
          height: show ? 52 : 0,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(color: show ? const Color(0x55000000) : const Color(0x00000000), blurRadius: 24, offset: const Offset(0, 10))],
          ), // fixed blur: lerping to null overshoots negative on the spring
          clipBehavior: Clip.hardEdge,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: Duration(milliseconds: show ? 350 : 120),
            curve: const Interval(.4, 1),
            child: data == null
                ? const SizedBox()
                : OverflowBox(
                    // The spring overshoots the target width, so pin both bounds.
                    minWidth: 0,
                    maxWidth: w - 28,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(color: ib, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: HIcon(data!.icon, size: 16, stroke: 2.4, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(data!.msg, maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
                        ),
                        // Cut off: a small arrow says there's more (tap to read it).
                        if (cut) ...[const SizedBox(width: 6), const HIcon('chev', size: 16, stroke: 2.4, color: Colors.white70)] else const SizedBox(width: 22),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Confetti extends StatefulWidget {
  const _Confetti({super.key});
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _P {
  double x, y, vx, vy, s, a, va;
  final Color c;
  final bool w;
  _P(this.x, this.y, this.vx, this.vy, this.s, this.c, this.a, this.va, this.w);
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2170))..forward();
  List<_P>? ps;
  int f = 0;
  static const cols = [Color(0xFF005BAC), Color(0xFFFF8A00), Color(0xFFF2EFE6), Color(0xFF771913), Color(0xFF5E9BD6)];

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      final target = (_c.value * 130).floor();
      while (f < target && ps != null) {
        for (final p in ps!) {
          p.vy += .32;
          p.vx *= .985;
          p.x += p.vx;
          p.y += p.vy;
          p.a += p.va;
        }
        f++;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, k) {
        final r = math.Random();
        ps ??= List.generate(
          110,
          (_) => _P(
            k.maxWidth / 2 + (r.nextDouble() - .5) * 60,
            k.maxHeight * .32,
            (r.nextDouble() - .5) * 9,
            -r.nextDouble() * 11 - 4,
            4 + r.nextDouble() * 6,
            cols[r.nextInt(cols.length)],
            r.nextDouble() * 6,
            (r.nextDouble() - .5) * .3,
            r.nextDouble() < .3,
          ),
        );
        return _c.isCompleted ? const SizedBox() : CustomPaint(painter: _ConfettiPainter(ps!, math.max(0, 1 - f / 120)), size: Size.infinite);
      },
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_P> ps;
  final double alpha;
  _ConfettiPainter(this.ps, this.alpha);
  @override
  void paint(Canvas canvas, Size size) {
    for (final p in ps) {
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.a);
      final paint = Paint()..color = p.c.withValues(alpha: alpha);
      if (p.w) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawPath(
          Path()
            ..moveTo(-6, 0)
            ..cubicTo(-2, -4, 2, 4, 6, 0),
          paint,
        );
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.s, height: p.s / 2), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
