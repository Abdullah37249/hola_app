import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../shared/widgets/logo.dart';
import '../../../shared/widgets/ui.dart';

/// Native launch colour (android `launch_navy`): the first frame matches it
/// exactly, so the hand-off from the system splash is invisible.
const kLaunchNavy = Color(0xFF000000);

/// Animated brand splash: the band gradient blooms out of the launch colour,
/// the logo springs in from a blur with two ripples, a shine sweeps across it,
/// the tagline rises and a progress line fills. Then it zooms gently away.
class SplashView extends StatefulWidget {
  final VoidCallback onDone;

  /// App data has loaded. The intro waits for it: loading blocks the UI
  /// thread, and an animation started earlier would play out unseen.
  final bool ready;
  const SplashView({super.key, required this.onDone, required this.ready});
  @override
  State<SplashView> createState() => _SplashState();
}

class _SplashState extends State<SplashView> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 2100));
  late final AnimationController _out = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
  // Slow drift for the background glows; runs for the whole splash.
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _maybeStart();
  }

  @override
  void didUpdateWidget(SplashView old) {
    super.didUpdateWidget(old);
    _maybeStart();
  }

  Future<void> _maybeStart() async {
    if (_started || !widget.ready) return;
    _started = true;
    // Let a couple of frames through first so the intro begins on a smooth clock.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _in.value = 1;
    } else {
      await _in.forward();
    }
    if (!mounted) return;
    await _out.forward();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _in.dispose();
    _out.dispose();
    _drift.dispose();
    super.dispose();
  }

  /// Progress of [from]..[to] within the intro, eased by [curve].
  double _seg(double from, double to, [Curve curve = Curves.easeOutCubic]) => curve.transform(((_in.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: _out.value > 0,
      child: AnimatedBuilder(
        animation: Listenable.merge([_in, _out, _drift]),
        builder: (context, _) {
          final out = Curves.easeInCubic.transform(_out.value);
          final bloom = _seg(0, .3);
          final logo = _seg(.08, .55, Curves.easeOutBack);
          final logoFade = _seg(.08, .4);
          final blur = 10 * (1 - _seg(.08, .5));
          final shine = _seg(.6, .92, Curves.easeInOut);
          final tag = _seg(.55, .85);
          final bar = _seg(.35, 1, Curves.easeInOutCubic);
          final d = Curves.easeInOut.transform(_drift.value);
          final ring = _seg(.05, .7, Curves.easeInOutCubic);
          return Opacity(
            opacity: 1 - out,
            child: Transform.scale(
              scale: 1 + .06 * out,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  const ColoredBox(color: kLaunchNavy),
                  // Night sky blooms out of the launch colour…
                  Opacity(
                    opacity: bloom,
                    child: const CustomPaint(painter: GlowRingPainter(progress: 0)),
                  ),
                  // …then the HOLA Circle draws itself in around the logo.
                  CustomPaint(
                    painter: GlowRingPainter(sky: false, center: const Alignment(0, -.06), scale: .46, progress: ring, phase: .08 * d, intensity: .6 + .4 * ring),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 280,
                          height: 140,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              _Ripple(t: _seg(.12, .75), color: const Color(0xFF6FB0FF)),
                              _Ripple(t: _seg(.24, .9), color: const Color(0xFFBFE0FF)),
                              Opacity(
                                opacity: logoFade,
                                child: Transform.scale(
                                  scale: .72 + .28 * logo + .04 * out,
                                  child: blur > .05
                                      ? ImageFiltered(
                                          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
                                          child: const Logo(height: 56, white: true),
                                        )
                                      : _Shine(t: shine, child: const Logo(height: 56, white: true)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Opacity(
                          opacity: tag,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - tag)),
                            child: Text(
                              tr('SALONS  ·  BOOKINGS  ·  PROFESSIONAL'),
                              style: TextStyle(
                                fontFamily: T.f,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2 + 2.5 * (1 - tag),
                                color: Colors.white.withValues(alpha: .8),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MediaQuery.paddingOf(context).bottom + 64,
                    child: Center(
                      child: Opacity(
                        opacity: math.min(1, bloom * 2) * (1 - _seg(.9, 1)),
                        child: Container(
                          width: 140,
                          height: 4,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .22), borderRadius: BorderRadius.circular(2)),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: math.max(.02, bar),
                            child: DecoratedBox(
                              decoration: BoxDecoration(gradient: G.progress, borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One expanding ring behind the logo; [t] runs 0→1.
class _Ripple extends StatelessWidget {
  final double t;
  final Color color;
  const _Ripple({required this.t, required this.color});
  @override
  Widget build(BuildContext context) {
    if (t <= 0 || t >= 1) return const SizedBox();
    return Transform.scale(
      scale: .5 + 1.9 * t,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: .55 * (1 - t)),
            width: 2.5 * (1 - t) + .5,
          ),
        ),
      ),
    );
  }
}

/// A diagonal highlight that sweeps across [child] once as [t] goes 0→1.
class _Shine extends StatelessWidget {
  final double t;
  final Widget child;
  const _Shine({required this.t, required this.child});
  @override
  Widget build(BuildContext context) {
    if (t <= 0 || t >= 1) return child;
    final x = -1.6 + 3.2 * t;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment(x - .5, -1),
        end: Alignment(x + .5, 1),
        colors: const [Color(0x006FB0FF), Color(0xFF9CCBFF), Color(0x006FB0FF)], // blue glint: the logo itself is white
        stops: const [.35, .5, .65],
      ).createShader(r),
      child: child,
    );
  }
}
