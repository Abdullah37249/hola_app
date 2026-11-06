import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:hola_professional/core/l10n/l10n.dart';
import 'package:hola_professional/core/utils/format.dart';
import 'package:hola_professional/core/utils/photo_files.dart';
import 'package:hola_professional/core/theme/icons.dart';
import 'package:hola_professional/core/utils/sfx.dart';
import 'package:hola_professional/core/theme/theme.dart';
import 'glow.dart';
import 'palette.dart';
import '../../domain/entities/status.dart';

export 'package:hola_professional/core/l10n/l10n.dart';
export 'package:hola_professional/core/theme/icons.dart';
export 'package:hola_professional/core/theme/theme.dart';
export 'fx.dart';
export 'glow.dart';
export 'states.dart';

// ───────────────────────── motion ─────────────────────────

/// Staggered "rise" entrance (prototype `.rv`). [i] is the stagger index.
/// "Reduce motion" in the phone's settings: a looping animation holds still
/// at [rest]; otherwise it keeps (or starts) looping.
void loopUnlessReduced(BuildContext context, AnimationController c, {bool reverse = false, double rest = 0}) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
    c
      ..stop()
      ..value = rest;
  } else if (!c.isAnimating) {
    c.repeat(reverse: reverse);
  }
}

class Reveal extends StatefulWidget {
  final Widget child;
  final int i;
  const Reveal({super.key, required this.child, this.i = 0});
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  // Made once (not per build, which leaked a listener on every rebuild).
  late final CurvedAnimation _a = CurvedAnimation(parent: _c, curve: kEase);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: math.min(widget.i, 12) * 45), () {
      if (mounted && !_c.isCompleted) _c.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Reduce motion" in the phone's settings: show it in place, no slide-in.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) _c.value = 1;
  }

  @override
  void dispose() {
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Already inside an animating Reveal (e.g. a staggered page): don't double the motion.
    if (context.dependOnInheritedWidgetOfExactType<_RevealScope>() != null) return widget.child;
    final a = _a;
    return AnimatedBuilder(
      animation: a,
      builder: (_, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - a.value)), child: child),
      ),
      child: _RevealScope(child: widget.child),
    );
  }
}

class _RevealScope extends InheritedWidget {
  const _RevealScope({required super.child});
  @override
  bool updateShouldNotify(_RevealScope old) => false;
}

/// Wraps a list of children in staggered [Reveal]s.
List<Widget> staggered(List<Widget> xs, [int from = 0]) => [for (var i = 0; i < xs.length; i++) Reveal(i: from + i, child: xs[i])];

/// Animated number count-up (prototype `countUp`, 900 ms).
class CountUp extends StatelessWidget {
  final num value;
  final String Function(num) format;
  final TextStyle? style;
  const CountUp(this.value, {super.key, this.format = _plain, this.style});
  static String _plain(num v) => v.round().toString();
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.toDouble()),
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (_, v, __) => Text(format(v), style: style),
  );
}

/// Press-to-scale wrapper with a tap sound.
class Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool sound;

  /// What a screen reader says for it (TalkBack / VoiceOver); without one it
  /// reads the text inside. Either way it's announced as a button.
  final String? label;
  const Tap({super.key, required this.child, this.onTap, this.scale = .97, this.sound = true, this.label});
  @override
  State<Tap> createState() => _TapState();
}

class _TapState extends State<Tap> {
  bool _d = false;
  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _d = true),
        onTapCancel: () => setState(() => _d = false),
        onTapUp: (_) => setState(() => _d = false),
        onTap: () {
          if (widget.sound) Sfx.tap();
          widget.onTap!();
        },
        child: AnimatedScale(scale: _d ? widget.scale : 1, duration: const Duration(milliseconds: 120), curve: kEase, child: widget.child),
      ),
    );
  }
}

// ───────────────────────── buttons ─────────────────────────

enum BtnKind { primary, secondary, ghost, soft, danger, dangerSoft, ok, white }

/// HOLA button: gradient primary with an animated shine, spring press,
/// spring press. When [onTap] returns a Future the button stays busy until it
/// completes: further taps are ignored and, if it takes a moment, a spinner shows.
class HButton extends StatefulWidget {
  final String label;
  final String? icon;
  final FutureOr<void> Function()? onTap;
  final BtnKind kind;
  final bool small, block;
  final bool sound;
  const HButton(this.label, {super.key, this.icon, this.onTap, this.kind = BtnKind.primary, this.small = false, this.block = false, this.sound = true});
  @override
  State<HButton> createState() => _HButtonState();
}

class _HButtonState extends State<HButton> with SingleTickerProviderStateMixin {
  bool _down = false, _busy = false, _spin = false;
  Timer? _spinCheck;
  AnimationController? _shine;

  @override
  void initState() {
    super.initState();
    // No looping shine: calmer, and no idle animation cost.
  }

  /// The page this button is on, looked up while the button is active (never
  /// from the timer: a button on a closing sheet must not look anything up).
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void deactivate() {
    _spinCheck?.cancel();
    super.deactivate();
  }

  @override
  void dispose() {
    _spinCheck?.cancel();
    _shine?.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (widget.onTap == null || _busy) return;
    if (widget.sound) Sfx.tap();
    final r = widget.onTap!();
    if (r is! Future) return;
    setState(() => _busy = true);
    // Spin only if the work isn't instant (no flicker on quick saves) and only
    // while this screen is in front: a tap that opens a sheet or page stays
    // busy (no double opens) without a spinner showing behind it.
    _spinCheck = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted || !_busy) return;
      final front = _route?.isCurrent ?? true;
      if (front != _spin) setState(() => _spin = front);
    });
    try {
      await r;
    } finally {
      _spinCheck?.cancel();
      if (mounted) setState(() => _busy = _spin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Gradient? g;
    Color? bg;
    Color fg;
    List<BoxShadow>? sh;
    Border? border;
    switch (widget.kind) {
      case BtnKind.primary:
        g = G.btn;
        fg = Colors.white;
        sh = const [BoxShadow(color: Color(0xCC2F80FF), blurRadius: 26, spreadRadius: -8, offset: Offset(0, 8))];
      case BtnKind.secondary:
        bg = c.surface;
        fg = c.brandText;
        border = Border.all(color: c.brand, width: 1.5);
      case BtnKind.ghost:
        bg = Colors.transparent;
        fg = c.ink;
      case BtnKind.soft:
        bg = c.surface;
        fg = c.ink;
        sh = c.lift;
      case BtnKind.danger:
        g = G.danger;
        fg = Colors.white;
        sh = const [BoxShadow(color: Color(0x99F61F1F), blurRadius: 22, spreadRadius: -10, offset: Offset(0, 10))];
      case BtnKind.dangerSoft:
        bg = c.badSoft;
        fg = c.badInk;
      case BtnKind.ok:
        g = G.ok;
        fg = Colors.white;
        sh = const [BoxShadow(color: Color(0xB314854E), blurRadius: 22, spreadRadius: -10, offset: Offset(0, 10))];
      case BtnKind.white:
        bg = Colors.white;
        fg = c.brand;
    }
    final disabled = widget.onTap == null;
    final h = widget.small ? 36.0 : 48.0;
    final content = _spin
        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) HIcon(widget.icon!, size: widget.small ? 18 : 20, color: fg),
              if (widget.icon != null && widget.label.isNotEmpty) SizedBox(width: widget.small ? 6 : 8),
              if (widget.label.isNotEmpty)
                Flexible(
                  // Shrink rather than truncate when a large system font makes the label too wide.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      style: TextStyle(fontFamily: T.f, fontWeight: FontWeight.w600, fontSize: widget.small ? 14 : 15, height: 20 / 15, letterSpacing: .2, color: fg),
                    ),
                  ),
                ),
            ],
          );
    return Opacity(
      opacity: disabled ? .4 : 1,
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => setState(() => _down = true),
        onTapUp: disabled ? null : (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: disabled ? null : _go,
        child: AnimatedScale(
          scale: _down ? .97 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            height: h,
            width: widget.block ? double.infinity : null,
            padding: EdgeInsets.symmetric(
              horizontal: widget.label.isEmpty
                  ? 0
                  : widget.small
                  ? 10
                  : 20,
            ),
            decoration: BoxDecoration(gradient: g, color: bg, borderRadius: BorderRadius.circular(h / 2), boxShadow: disabled ? null : sh, border: border),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_shine != null)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _shine!,
                      builder: (_, __) {
                        // shine sweeps during the first ~40% of each cycle
                        final t = (_shine!.value / .4).clamp(0.0, 1.0);
                        return FractionalTranslation(
                          translation: Offset(-1.3 + 2.6 * Curves.easeInOut.transform(t), 0),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [Color(0x00FFFFFF), Color(0x59FFFFFF), Color(0x00FFFFFF)], stops: [.3, .5, .7]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round 44px icon button. [onBand] renders the frosted white style used on gradient bands.
class IconBtn extends StatelessWidget {
  final String icon;
  final VoidCallback? onTap;
  final int dot;
  final bool onBand, raised;
  final Color? color;

  /// Spoken name for this icon-only button; defaults from the icon.
  final String? label;
  const IconBtn(this.icon, {super.key, this.onTap, this.dot = 0, this.onBand = false, this.raised = false, this.color, this.label});

  static String? _named(String icon) => switch (icon) {
    'back' => 'Back',
    'x' => 'Close',
    'phone' => 'Call',
    'bell' => 'Notifications',
    'heart' => 'Save salon',
    'map' => 'Show map',
    'list' => 'Show list',
    'search' => 'Search',
    'filter' => 'Filter',
    'edit' => 'Edit',
    'msg' => 'Message',
    'check' => 'Mark all as read',
    'chev' => 'Open',
    'clip' => 'Copy',
    'more' || 'grid' => 'More',
    _ => null,
  };
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final spoken = label ?? (_named(icon) == null ? null : tr(_named(icon)!));
    return Tap(
      onTap: onTap,
      scale: .92,
      label: spoken,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onBand
                    ? Colors.white.withValues(alpha: .18)
                    : raised
                    ? c.surface
                    : Colors.transparent,
                border: onBand ? Border.all(color: Colors.white.withValues(alpha: .25)) : null,
                boxShadow: raised ? c.lift : null,
              ),
              alignment: Alignment.center,
              child: HIcon(icon, color: color ?? (onBand ? Colors.white : c.ink)),
            ),
            if (dot > 0)
              Positioned(
                top: 4,
                right: 2,
                child: _Pulse(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(9)),
                    alignment: Alignment.center,
                    child: Text(
                      '$dot',
                      style: const TextStyle(fontFamily: T.f, color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopUnlessReduced(context, _c, rest: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A00).withValues(alpha: .7 * (1 - _c.value)),
            spreadRadius: 8 * _c.value,
          ),
        ],
      ),
      child: child,
    ),
    child: widget.child,
  );
}

// ───────────────────────── surfaces ─────────────────────────

class HCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final double radius;
  final List<BoxShadow>? shadow;
  final Border? border;
  const HCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.gradient, this.radius = 16, this.shadow, this.border});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? context.c.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ?? context.c.lift,
        border:
            border ??
            (gradient == null
                ? Border.all(
                    color: context.c.line.withValues(alpha: context.c.dark ? 1 : .7),
                    width: context.c.dark ? .8 : .6,
                  )
                : null),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
    return onTap == null ? box : Tap(onTap: onTap, scale: .985, child: box);
  }
}

/// Status badge (prototype `badge()`); [live] blinks its dot.
class StatusBadge extends StatelessWidget {
  final String status;
  final String? label;
  const StatusBadge(this.status, {super.key, this.label});
  @override
  Widget build(BuildContext context) {
    final s = statusLabels[status] ?? (status, 'mute', false);
    return ToneBadge(label ?? s.$1, tone: s.$2, live: s.$3);
  }
}

class ToneBadge extends StatelessWidget {
  final String label, tone;
  final bool live;
  const ToneBadge(this.label, {super.key, this.tone = 'mute', this.live = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = switch (tone) {
      'ok' => (c.okSoft, c.ok),
      'warn' => (c.accentSoft, c.accentInk),
      'bad' => (c.badSoft, c.badInk),
      'info' => (c.brandSoft, c.brandText),
      _ => (c.bg2, c.muted),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          live ? _Blink(child: _dot(fg)) : _dot(fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: T.f, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: fg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );
}

class _Blink extends StatefulWidget {
  final Widget child;
  const _Blink({required this.child});
  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopUnlessReduced(context, _c, reverse: true, rest: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: Tween(begin: 1.0, end: .25).animate(_c), child: widget.child);
}

// ───────────────────────── inputs ─────────────────────────

/// Selectable chip; selected state uses the brand gradient.
class HChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  final String? icon;
  const HChip(this.label, {super.key, this.on = false, this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tap(
      onTap: onTap == null
          ? null
          : () {
              Sfx.toggle();
              onTap!();
            },
      sound: false,
      scale: .96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        // Night: selected is the poster's white pill with dark type. Light: brand blue.
        decoration: BoxDecoration(
          gradient: on && !c.dark ? G.btn : null,
          color: on ? (c.dark ? Colors.white : null) : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: on ? null : Border.all(color: c.line),
          boxShadow: on ? [BoxShadow(color: c.dark ? const Color(0x806FB0FF) : const Color(0xB32F80FF), blurRadius: 18, spreadRadius: -8, offset: const Offset(0, 6))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[HIcon(icon!, size: 16, color: on ? (c.dark ? c.night : Colors.white) : c.ink), const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(fontFamily: T.f, fontSize: 14, height: 20 / 14, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? (c.dark ? c.night : Colors.white) : c.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal scrolling chip row.
class ChipRow extends StatelessWidget {
  final List<Widget> children;
  const ChipRow({super.key, required this.children});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 8), children[i]],
      ],
    ),
  );
}

/// Segmented control with a sliding gradient indicator.
class Seg extends StatelessWidget {
  final List<(String, String)> opts; // (value, label)
  final String value;
  final ValueChanged<String> onChanged;
  final bool onBand;
  const Seg({super.key, required this.opts, required this.value, required this.onChanged, this.onBand = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final i = math.max(0, opts.indexWhere((o) => o.$1 == value));
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: onBand ? Colors.white.withValues(alpha: .2) : c.bg2, borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(
        builder: (context, k) {
          final w = k.maxWidth / opts.length;
          return SizedBox(
            height: 36,
            child: Stack(
              children: [
                // Directional, so the highlight follows the option in Urdu (right to left).
                AnimatedPositionedDirectional(
                  duration: const Duration(milliseconds: 300),
                  curve: kSpring,
                  start: w * i,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: onBand ? null : G.btn,
                      color: onBand ? Colors.white : null,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [BoxShadow(color: Color(0xB32F80FF), blurRadius: 14, spreadRadius: -6, offset: Offset(0, 6))],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final o in opts)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (o.$1 != value) {
                              Sfx.toggle();
                              onChanged(o.$1);
                            }
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontFamily: T.f,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: o.$1 == value ? (onBand ? c.brand : Colors.white) : (onBand ? Colors.white : c.muted),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: FittedBox(fit: BoxFit.scaleDown, child: Text(o.$2, maxLines: 1)),
                              ), // shrink, don't truncate, with large text
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class HSwitch extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const HSwitch({super.key, required this.on, required this.onChanged});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      Sfx.toggle();
      onChanged(!on);
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 50,
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(gradient: on ? G.btn : null, color: on ? null : context.c.line, borderRadius: BorderRadius.circular(15)),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 300),
        curve: kSpring,
        alignment: on ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1))],
          ),
        ),
      ),
    ),
  );
}

class HStepper extends StatelessWidget {
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const HStepper({super.key, required this.value, required this.onChanged, this.min = 0, this.max = 999});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget b(String ic, int d) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final v = value + d;
        if (v >= min && v <= max) {
          d > 0 ? Sfx.add() : Sfx.tap();
          onChanged(v);
        }
      },
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(child: HIcon(ic, size: 18, color: c.ink)),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b('minus', -1),
          SizedBox(
            width: 28,
            child: Text('$value', textAlign: TextAlign.center, style: T.ttl(context)),
          ),
          b('plus', 1),
        ],
      ),
    );
  }
}

/// Labelled text field (prototype `.field` + `.input`).
/// Per-form field errors. A form makes one, passes it to its [HField]s (each
/// with a [HField.name]) and to `attempt(errors: ...)`; a [DomainError] whose
/// `field` matches a registered name then shows under that field instead of
/// as a toast. Typing in the field clears its error.
class FieldErrors extends ChangeNotifier {
  final _errors = <String, String>{};
  final _known = <String>{};
  String? of(String name) => _errors[name];
  bool knows(String? name) => name != null && _known.contains(name);
  void register(String name) => _known.add(name);
  void set(String name, String message) {
    _errors
      ..clear()
      ..[name] = message;
    notifyListeners();
  }

  void clear(String name) {
    if (_errors.remove(name) != null) notifyListeners();
  }
}

class HField extends StatelessWidget {
  final String? label, hint, helper, icon, initial;
  final TextEditingController? controller;
  final bool obscure, multiline;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final Widget? suffix;

  /// Keyboard action. Defaults to Next (moves to the following field), or a new line when [multiline].
  final TextInputAction? action;

  /// Called when the keyboard action is pressed; use it on a form's last field to submit.
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofill;
  final TextCapitalization caps;

  /// Key this field answers to in [errors] (matches `DomainError.field`).
  final String? name;
  final FieldErrors? errors;
  const HField({
    super.key,
    this.label,
    this.hint,
    this.helper,
    this.icon,
    this.initial,
    this.controller,
    this.obscure = false,
    this.multiline = false,
    this.keyboard,
    this.onChanged,
    this.validator,
    this.suffix,
    this.action,
    this.onSubmitted,
    this.autofill,
    this.caps = TextCapitalization.none,
    this.name,
    this.errors,
  });
  @override
  Widget build(BuildContext context) {
    final errs = errors, key = name;
    if (errs == null || key == null) return _build(context, null);
    errs.register(key);
    return ListenableBuilder(listenable: errs, builder: (context, _) => _build(context, errs.of(key)));
  }

  /// Field label style; use it to label chips, steppers and other inputs in the same form.
  static TextStyle labelStyle(BuildContext context) => TextStyle(fontFamily: T.f, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w600, color: context.c.ink);

  Widget _build(BuildContext context, String? error) {
    final c = context.c;
    OutlineInputBorder ob(Color col, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: col, width: w),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[Text(label!, style: labelStyle(context).copyWith(color: error != null ? c.badInk : null)), const SizedBox(height: 6)],
        _Shake(
          trigger: error,
          child: _FocusGlow(
            builder: (focused) => TextFormField(
              controller: controller,
              initialValue: controller == null ? initial : null,
              obscureText: obscure,
              minLines: multiline ? 3 : 1,
              maxLines: multiline ? 5 : 1,
              keyboardType: keyboard ?? (multiline ? TextInputType.multiline : null),
              textInputAction: action ?? (multiline ? TextInputAction.newline : TextInputAction.next),
              textCapitalization: multiline && caps == TextCapitalization.none ? TextCapitalization.sentences : caps,
              autofillHints: autofill,
              autocorrect: !obscure && keyboard != TextInputType.emailAddress,
              enableSuggestions: !obscure,
              onFieldSubmitted: onSubmitted,
              onChanged: (v) {
                if (name != null) errors?.clear(name!);
                onChanged?.call(v);
              },
              validator: validator,
              style: TextStyle(fontFamily: T.f, fontSize: 16, fontWeight: FontWeight.w500, color: c.ink),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: c.subtle),
                filled: true,
                fillColor: c.surface,
                isDense: true,
                errorText: error,
                errorMaxLines: 3,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                prefixIcon: icon == null
                    ? null
                    : Padding(
                        padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
                        child: AnimatedScale(
                          scale: focused ? 1.1 : 1,
                          duration: const Duration(milliseconds: 220),
                          curve: kSpring,
                          child: HIcon(
                            icon!,
                            size: 20,
                            color: error != null
                                ? c.bad
                                : focused
                                ? c.brand
                                : c.muted,
                          ),
                        ),
                      ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0),
                suffixIcon: suffix == null ? null : ExcludeFocus(child: suffix!), // Next skips the eye button
                enabledBorder: ob(c.line),
                border: ob(c.line),
                focusedBorder: ob(c.brand, 1.5),
                errorBorder: ob(c.bad),
                focusedErrorBorder: ob(c.bad, 1.5),
                errorStyle: TextStyle(color: c.badInk, fontSize: 12),
              ),
            ),
          ),
        ),
        if (helper != null && error == null) ...[const SizedBox(height: 6), Text(helper!, style: T.cap(context))],
      ],
    );
  }
}

/// Quick side-to-side shake whenever [trigger] changes to a new non-null value.
class _Shake extends StatelessWidget {
  final Object? trigger;
  final Widget child;
  const _Shake({required this.trigger, required this.child});
  @override
  Widget build(BuildContext context) {
    if (trigger == null) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      builder: (_, t, child) => Transform.translate(offset: Offset(8 * math.sin(t * math.pi * 4) * (1 - t), 0), child: child),
      child: child,
    );
  }
}

/// Soft brand halo around a field while it has focus.
class _FocusGlow extends StatefulWidget {
  final Widget Function(bool focused) builder;
  const _FocusGlow({required this.builder});
  @override
  State<_FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<_FocusGlow> {
  bool _f = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (f) => setState(() => _f = f),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: kEase,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: context.c.brand.withValues(alpha: _f ? .22 : 0), blurRadius: 16, spreadRadius: -2)],
      ),
      child: widget.builder(_f),
    ),
  );
}

// ───────────────────────── lists ─────────────────────────

/// Grouped menu card (prototype `.group`).
class Group extends StatelessWidget {
  final List<Widget> children;
  const Group({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), boxShadow: c.lift),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) Divider(height: 1, thickness: 1, color: c.line), children[i]],
        ],
      ),
    );
  }
}

/// Menu row with tinted icon tile. [tint] cycles brand / accent / ok like the prototype.
class MRow extends StatelessWidget {
  final String icon, title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int tint;
  final Color? titleColor;
  const MRow({super.key, required this.icon, required this.title, this.sub, this.trailing, this.onTap, this.tint = 0, this.titleColor});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // One calm tint for every row; [tint] is kept for call-site compatibility.
    // A coloured title (e.g. a destructive row) colours its icon to match.
    final (bg, fg) = titleColor == null ? (c.brandSoft, c.brandText) : (titleColor!.withValues(alpha: .1), titleColor!);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                Sfx.tap();
                onTap!();
              },
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: HIcon(icon, size: 20, color: fg),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontFamily: T.f, fontSize: 16, fontWeight: FontWeight.w500, color: titleColor ?? c.ink),
                    ),
                    if (sub != null && sub!.isNotEmpty)
                      Text(
                        sub!,
                        style: TextStyle(fontFamily: T.f, fontSize: 13, height: 18 / 13, color: c.muted),
                      ),
                  ],
                ),
              ),
              trailing ?? (onTap != null ? HIcon('chev', size: 18, color: c.subtle) : const SizedBox()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section header: title with an optional text action.
class SecHead extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SecHead(this.title, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: Text(title, style: T.h3(context).copyWith(fontSize: 18))),
      if (action != null)
        GestureDetector(
          onTap: () {
            Sfx.tap();
            onAction?.call();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(action!, style: T.link(context)),
          ),
        ),
    ],
  );
}

/// Key/value line.
class KV extends StatelessWidget {
  final String k, v;
  final Color? vColor;
  const KV(this.k, this.v, {super.key, this.vColor});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A long label wraps (at most 60% of the row) instead of pushing the value off.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth.isFinite ? box.maxWidth * .6 : double.infinity),
            child: Text(k, style: T.sm(context).copyWith(color: context.c.muted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: T.sm(context).copyWith(color: vColor ?? context.c.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

class HDivider extends StatelessWidget {
  const HDivider({super.key});
  @override
  Widget build(BuildContext context) => Divider(height: 1, thickness: 1, color: context.c.line);
}

class EmptyState extends StatelessWidget {
  final String icon, title, text;
  final Widget? cta;
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.cta});
  @override
  Widget build(BuildContext context) => Reveal(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          _Float(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [context.c.brand.withValues(alpha: .16), context.c.accent.withValues(alpha: .16)]),
              ),
              alignment: Alignment.center,
              child: HIcon(icon, size: 30, color: context.c.brandText),
            ),
          ),
          const SizedBox(height: 14),
          Text(title, style: T.h3(context), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            text,
            style: T.sm(context).copyWith(color: context.c.muted),
            textAlign: TextAlign.center,
          ),
          if (cta != null) ...[const SizedBox(height: 12), cta!],
        ],
      ),
    ),
  );
}

/// Slow up-and-down bob for idle illustrations.
class _Float extends StatefulWidget {
  final Widget child;
  const _Float({required this.child});
  @override
  State<_Float> createState() => _FloatState();
}

class _FloatState extends State<_Float> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopUnlessReduced(context, _c, reverse: true, rest: .5);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Transform.translate(offset: Offset(0, -5 * Curves.easeInOut.transform(_c.value)), child: child),
    child: widget.child,
  );
}

// ───────────────────────── art ─────────────────────────

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final int? k;
  const Avatar(this.name, {super.key, this.size = 40, this.k});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Color(avatarColors[(k ?? name.length) % avatarColors.length]),
      shape: BoxShape.circle,
      border: Border.all(color: context.c.surface, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, spreadRadius: -6, offset: Offset(0, 6))],
    ),
    alignment: Alignment.center,
    child: Text(
      initials(name),
      style: TextStyle(fontFamily: T.f, color: Colors.white, fontWeight: FontWeight.w600, fontSize: (size * .36).roundToDouble(), letterSpacing: .3),
    ),
  );
}

/// Generative salon interior: three arched mirrors over a counter line.
class SalonArt extends StatelessWidget {
  final int p;
  final int n; // kept for call-site compatibility (motif density)
  final double? height;
  final double radius;
  final Widget? child;

  /// When given, the salon's initials are set in the display serif.
  final String? name;

  /// Cover photo file name; shown instead of the artwork when it's on this device.
  final String? photo;
  const SalonArt(this.p, {super.key, this.n = 3, this.height, this.radius = 18, this.child, this.name, this.photo});
  @override
  Widget build(BuildContext context) {
    final cs = pal[p % pal.length].map(Color.new).toList();
    final file = PhotoFiles.file(photo);
    final url = photo != null && photo!.startsWith('https://') ? photo : null; // HOLA salons: public photo links
    Widget fade(BuildContext _, Widget child, int? frame, bool sync) => sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 300), child: child);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _ArtPainter(cs[0], cs[1], cs[2], n)),
            if (file != null)
              // Fades in over the artwork once decoded; the artwork stays as the fallback.
              Image.file(file, fit: BoxFit.cover, cacheWidth: 1200, frameBuilder: fade, errorBuilder: (_, __, ___) => const SizedBox())
            else if (url != null)
              Image.network(url, fit: BoxFit.cover, cacheWidth: 1200, frameBuilder: fade, errorBuilder: (_, __, ___) => const SizedBox())
            else if (name != null && name!.trim().isNotEmpty)
              LayoutBuilder(
                builder: (_, k) => Center(
                  child: Text(
                    initials(name!).toUpperCase(),
                    style: TextStyle(fontFamily: T.head, fontSize: (k.biggest.shortestSide * .42).clamp(14, 72), height: 1, color: Colors.white.withValues(alpha: .92), letterSpacing: 1),
                  ),
                ),
              ),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

/// Abstract cover: deep tone, soft light, and concentric rings echoing a
/// salon mirror. Calm and premium rather than illustrative.
class _ArtPainter extends CustomPainter {
  final Color a, b, cc;
  final int n;
  _ArtPainter(this.a, this.b, this.cc, this.n);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    final base = Color.lerp(a, const Color(0xFF0B1B33), .25)!;
    canvas.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(base, b, .35)!, base]).createShader(r));
    canvas.drawRect(r, Paint()..shader = RadialGradient(center: const Alignment(.8, -.9), radius: 1, colors: [b.withValues(alpha: .55), b.withValues(alpha: 0)]).createShader(r));
    final center = Offset(s.width * .78, s.height * .2);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, s.shortestSide * .012)
      ..color = Colors.white.withValues(alpha: .14);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, s.longestSide * .16 * i, ring);
    }
    canvas.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: .18)]).createShader(r));
  }

  @override
  bool shouldRepaint(covariant _ArtPainter o) => o.a != a || o.b != b;
}

/// CSS-style product bottle (shapes: '', jar, tube, drop, spray, tubcol).
class Bottle extends StatelessWidget {
  final int color;
  final String shape;
  final double height;
  final double scale;
  const Bottle({super.key, required this.color, this.shape = '', this.height = 150, this.scale = 1});
  @override
  Widget build(BuildContext context) {
    final pc = Color(color);
    final c = context.c;
    final (w, h, r) = switch (shape) {
      'jar' => (76.0, 56.0, const BorderRadius.all(Radius.circular(10))),
      'tube' => (40.0, 108.0, const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(16))),
      'drop' => (42.0, 70.0, const BorderRadius.all(Radius.circular(10))),
      'tubcol' => (34.0, 100.0, const BorderRadius.all(Radius.circular(5))),
      _ => (46.0, 96.0, const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(9))),
    };
    final (cw, ch, ctop) = switch (shape) {
      'jar' => (82.0, 16.0, -14.0),
      'tube' => (26.0, 12.0, h - 2),
      'drop' => (14.0, 30.0, -28.0),
      'spray' => (16.0, 22.0, -20.0),
      _ => (22.0, 18.0, -16.0),
    };
    final bottle = SizedBox(
      width: math.max(w, cw),
      height: h + 30,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                borderRadius: r,
                color: pc,
                gradient: LinearGradient(colors: [Color.alphaBlend(Colors.white.withValues(alpha: .28), pc), pc, Color.alphaBlend(Colors.black.withValues(alpha: .16), pc)], stops: const [0, .38, 1]),
                boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 16, spreadRadius: -10, offset: Offset(0, 12))],
              ),
              child: Align(
                alignment: Alignment(0, shape == 'jar' ? -.3 : -.1),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(2)),
                  child: const Text(
                    'HOLA',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: T.f, fontSize: 8, height: 1, fontWeight: FontWeight.w600, letterSpacing: 1.9, color: Color(0xFF1D1D1F)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: shape == 'tube' ? -10 : h - ctop - ch + 0,
            child: Container(
              width: cw,
              height: ch,
              decoration: BoxDecoration(
                color: const Color(0xFF1D1D1F),
                borderRadius: shape == 'drop'
                    ? const BorderRadius.vertical(top: Radius.circular(99), bottom: Radius.circular(3))
                    : shape == 'tube'
                    ? const BorderRadius.vertical(top: Radius.circular(2), bottom: Radius.circular(6))
                    : const BorderRadius.vertical(top: Radius.circular(4), bottom: Radius.circular(2)),
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      height: height,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.alphaBlend(pc.withValues(alpha: .14), c.surface), c.surface]),
        boxShadow: c.lift,
      ),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: -10,
            child: Container(
              width: 120,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [pc.withValues(alpha: .4), pc.withValues(alpha: 0)]),
              ),
            ),
          ),
          Transform.scale(scale: scale, alignment: Alignment.bottomCenter, child: bottle),
        ],
      ),
    );
  }
}

class Stars extends StatelessWidget {
  final int n;
  final double size;
  const Stars(this.n, {super.key, this.size = 14});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [for (var i = 0; i < 5; i++) HIcon('star', size: size, fill: true, color: i < n ? context.c.accent : context.c.line)],
  );
}

class RatingTag extends StatelessWidget {
  final double rating;
  final Color? color;
  const RatingTag(this.rating, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      HIcon('star', size: 14, fill: true, color: context.c.accent),
      const SizedBox(width: 4),
      Text(
        '$rating',
        style: TextStyle(fontFamily: T.f, fontWeight: FontWeight.w600, fontSize: 14, color: color ?? context.c.ink),
      ),
    ],
  );
}

/// Gradient progress bar.
class HProgress extends StatelessWidget {
  final double value;
  final double height;
  const HProgress(this.value, {super.key, this.height = 8});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: Container(
      height: height,
      color: context.c.bg2,
      alignment: Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 900),
        curve: kEase,
        builder: (_, v, __) => FractionallySizedBox(
          widthFactor: v,
          child: Container(decoration: const BoxDecoration(gradient: G.progress)),
        ),
      ),
    ),
  );
}

// ───────────────────────── sheets ─────────────────────────

/// Creates [V] once and disposes it only when this widget leaves the tree,
/// so a sheet's controller lives through its closing animation.
class Owned<V> extends StatefulWidget {
  final V Function() create;
  final void Function(V) dispose;
  final Widget Function(BuildContext, V) builder;
  const Owned({super.key, required this.create, required this.dispose, required this.builder});
  @override
  State<Owned<V>> createState() => _OwnedState<V>();
}

class _OwnedState<V> extends State<Owned<V>> {
  late final V value = widget.create();
  @override
  void dispose() {
    widget.dispose(value);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, value);
}

/// Bottom sheet with grab handle, blur backdrop and 26px top radius.
Future<R?> showHSheet<R>(BuildContext context, Widget Function(BuildContext) builder) {
  Sfx.sheet();
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.c.surface,
    barrierColor: context.c.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(kGutter, 8, kGutter, 28 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(top: 4, bottom: 14),
                decoration: BoxDecoration(color: ctx.c.line, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Reveal(i: 1, child: builder(ctx)),
          ],
        ),
      ),
    ),
  );
}

/// Standard sheet header: title + optional subtitle.
class SheetHead extends StatelessWidget {
  final String title;
  final String? sub;
  const SheetHead(this.title, {super.key, this.sub});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: T.h2(context)),
        if (sub != null) ...[const SizedBox(height: 4), Text(sub!, style: T.sm(context).copyWith(color: context.c.muted))],
      ],
    ),
  );
}

// ───────────────────────── page scaffolds ─────────────────────────

/// Every tab screen's header is this tall below the status bar, so the band is
/// the same size on all screens (customer, salon and the rest).
const kBandBody = 250.0;

/// The salon Today header (greeting + number cards across the edge), below
/// the status bar. Every screen with a [BandMark.match] container is padded to
/// end its header exactly here, so customer and salon headers are one size.
const kTodayBand = 190.0;

/// The header band: a royal-blue sky crossed by fine lines of light that
/// meet in a soft glow, an orange HOLA dot, and a double wave into the page.
class Band extends StatelessWidget {
  final String role;
  final double height;
  const Band({super.key, required this.role, this.height = 290});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(
      painter: HolaSkyPainter(page: context.c.bg, dark: context.c.dark),
    ),
  );
}

/// Paints the HOLA header (see [Band]). [page] is the colour below the wave.
class HolaSkyPainter extends CustomPainter {
  final Color page;
  final bool dark;
  HolaSkyPainter({required this.page, this.dark = false});

  static const _top = Color(0xFF083C8D), _mid = Color(0xFF062D6A), _low = Color(0xFF051742);
  static const wave = 48.0; // depth of the wave area at the bottom

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final rect = Offset.zero & s;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h + 2));
    // Sky: bright royal blue fading to deep navy.
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_top, _mid, _low], stops: [0, .55, 1]).createShader(rect));

    // Where the lines meet, with a soft glow.
    final f = Offset(w * .8, (h - wave) * .42);
    canvas.drawCircle(
      f,
      w * .42,
      Paint()..shader = RadialGradient(colors: [Colors.white.withValues(alpha: .10), Colors.white.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: f, radius: w * .42)),
    );
    // A wide wash of light behind the right side.
    final wash = Offset(w * .95, h * .2);
    canvas.drawCircle(
      wash,
      w * .55,
      Paint()
        ..shader = RadialGradient(colors: [const Color(0xFF6FA8FF).withValues(alpha: .16), const Color(0xFF6FA8FF).withValues(alpha: 0)]).createShader(Rect.fromCircle(center: wash, radius: w * .55)),
    );

    Paint line(double a, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = Colors.white.withValues(alpha: a);
    Paint halo(double a) => line(a, 5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // 1. A large circle whose left edge runs down through the meeting point.
    final r1 = w * .62;
    final c1 = Offset(f.dx + r1, f.dy + r1 * .06);
    canvas.drawCircle(c1, r1, halo(.07));
    canvas.drawCircle(c1, r1, line(.34, 1.1));
    // 2. A second, fainter circle sweeping in from the top.
    final c2 = Offset(w * 1.08, -h * .32);
    final r2 = (f - c2).distance;
    canvas.drawCircle(c2, r2, line(.2, 1));
    // 3. Two long rays through the meeting point.
    void ray(double deg, double a) {
      final d = Offset.fromDirection(deg * math.pi / 180);
      canvas.drawLine(f - d * w * 2, f + d * w * 2, line(a, 1));
    }

    ray(-31, .22);
    // The meeting point itself.
    canvas.drawCircle(
      f,
      2.5,
      Paint()
        ..color = Colors.white.withValues(alpha: .55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // The orange HOLA dot, sitting on the big circle below the meeting point.
    final dotAngle = math.pi - .22;
    final dot = c1 + Offset.fromDirection(dotAngle, r1);
    canvas.drawCircle(dot, 6.5, Paint()..color = const Color(0xFFFF8A00));
    canvas.drawCircle(
      dot,
      12,
      Paint()
        ..color = const Color(0xFFFF8A00).withValues(alpha: .25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Double wave: a translucent ribbon, then the page in front of it.
    Path waveAt(double lift) {
      final b = h - wave - lift;
      return Path()
        ..moveTo(0, b + wave * .08)
        ..cubicTo(w * .02, b + wave * .62, w * .1, b + wave * .78, w * .24, b + wave * .86)
        ..cubicTo(w * .42, b + wave * .98, w * .6, b + wave * .9, w * .76, b + wave * .66)
        ..cubicTo(w * .86, b + wave * .52, w * .94, b + wave * .54, w, b + wave * .6)
        ..lineTo(w, h + 2)
        ..lineTo(0, h + 2)
        ..close();
    }

    canvas.drawPath(waveAt(14), Paint()..color = (dark ? const Color(0xFF7FA6E8) : Colors.white).withValues(alpha: dark ? .22 : .38));
    canvas.drawPath(waveAt(0), Paint()..color = page);
    canvas.restore();
  }

  @override
  bool shouldRepaint(HolaSkyPainter o) => o.page != page || o.dark != dark;
}

/// Marks the container that sits across the header's wave edge (summary
/// numbers, search bar, credit card…). The band ends through its middle, so
/// it always sits half on the blue and half on the page. Place it as a direct
/// child of the view's list (not inside a [Reveal]).
///
/// With [match], the container is pushed down so the header ends exactly at
/// [kTodayBand], the salon Today height, on every screen that uses it.
class BandMark extends StatelessWidget {
  final Widget? child;
  final bool match;
  const BandMark({super.key, this.child, this.match = false});
  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_BandScope>();
    final key = scope?.mark;
    if (child == null) return SizedBox(key: key, height: 0);
    scope?.match.value = match;
    if (!match || scope == null) return KeyedSubtree(key: key, child: child!);
    return ValueListenableBuilder<double>(
      valueListenable: scope.pad,
      builder: (_, pad, c) => Padding(
        key: key,
        padding: EdgeInsets.only(top: pad),
        child: c,
      ),
      child: child,
    );
  }
}

class _BandScope extends InheritedWidget {
  final GlobalKey mark;
  final ValueNotifier<double> pad;
  final ValueNotifier<bool> match;
  const _BandScope({required this.mark, required this.pad, required this.match, required super.child});
  @override
  bool updateShouldNotify(_BandScope old) => old.mark != mark;
}

/// Tab view scaffold: gradient band + scrolling content with gutter.
/// Header widgets placed in [header] sit on the band (white text).
class BandView extends StatefulWidget {
  final String role;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double bandHeight;
  const BandView({super.key, required this.role, required this.children, this.onRefresh, this.bandHeight = 290});
  @override
  State<BandView> createState() => _BandViewState();
}

class _BandViewState extends State<BandView> {
  bool _scrolled = false;
  final _offset = ValueNotifier(0.0);
  final _mark = GlobalKey();
  double? _markedHeight;

  /// Ends the band through the middle of the [BandMark]'s container (the
  /// wave runs behind it); screens without one use the standard height.
  final _pad = ValueNotifier(0.0);
  final _match = ValueNotifier(false);

  void _measure() {
    if (!mounted) return;
    final mark = _mark.currentContext?.findRenderObject() as RenderBox?;
    final me = context.findRenderObject() as RenderBox?;
    if (mark == null || me == null || !mark.attached) return;
    final y = mark.localToGlobal(Offset.zero, ancestor: me).dy + _offset.value;
    final ref = MediaQuery.paddingOf(context).top + kTodayBand;
    double h;
    if (_match.value && mark.size.height > 0) {
      // Move the container down so its middle sits on the reference edge.
      final childH = mark.size.height - _pad.value;
      final pad = math.max(0.0, ref - (y + childH / 2 + HolaSkyPainter.wave / 2));
      if ((pad - _pad.value).abs() > 1) _pad.value = pad;
      h = (y + pad + childH / 2 + HolaSkyPainter.wave / 2).roundToDouble();
    } else {
      h = (mark.size.height > 0 ? y + mark.size.height / 2 + HolaSkyPainter.wave / 2 : y + 24).roundToDouble();
    }
    if (_markedHeight == null || (h - _markedHeight!).abs() > 1) setState(() => _markedHeight = h);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      _offset.value = math.max(0, n.metrics.pixels);
      final s = n.metrics.pixels > 24;
      if (s != _scrolled) setState(() => _scrolled = s);
    }
    return false;
  }

  @override
  void dispose() {
    _pad.dispose();
    _match.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final list = _BandScope(
      mark: _mark,
      pad: _pad,
      match: _match,
      child: ListView(padding: EdgeInsets.fromLTRB(kGutter, top + 12, kGutter, 128 + MediaQuery.paddingOf(context).bottom), children: widget.children),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Stack(
      children: [
        // The band scrolls away with the content so cards never sit on top of it.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<double>(
            valueListenable: _offset,
            builder: (_, y, child) => Transform.translate(offset: Offset(0, -y), child: child),
            child: Band(role: widget.role, height: _markedHeight ?? top + kBandBody),
          ),
        ),
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.onRefresh == null ? list : RefreshIndicator(onRefresh: widget.onRefresh!, color: context.c.brand, child: list),
        ),
        Positioned(top: 0, left: 0, right: 0, child: StatusScrim(show: _scrolled)),
      ],
    );
  }
}

/// Frosted strip behind the system status bar, shown once content scrolls
/// under it so the clock and icons stay readable. [child] sits below the
/// status bar inside the strip (e.g. a compact title).
class StatusScrim extends StatelessWidget {
  final bool show;
  final Widget? child;
  final double height;
  const StatusScrim({super.key, required this.show, this.child, this.height = 0});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = MediaQuery.paddingOf(context).top;
    return IgnorePointer(
      ignoring: !show,
      child: AnimatedOpacity(
        opacity: show ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: top + height,
              padding: EdgeInsets.only(top: top),
              decoration: BoxDecoration(
                color: c.glass,
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Header row for tab views on the band: eyebrow + title + trailing actions.
class TopHead extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? sub;
  final List<Widget> actions;
  final bool onBand;

  /// Keep the title on one line, shrinking a long name to fit.
  final bool oneLine;
  const TopHead({super.key, this.eyebrow, required this.title, this.sub, this.actions = const [], this.onBand = true, this.oneLine = false});
  @override
  Widget build(BuildContext context) {
    final fg = onBand ? Colors.white : context.c.ink;
    // A tab screen opened as its own page (e.g. Team from More) gets a back button.
    final inPage = context.dependOnInheritedWidgetOfExactType<InPage>() != null;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (inPage) ...[
            IconBtn(
              'back',
              onBand: onBand,
              onTap: () {
                Sfx.back();
                Navigator.of(context).maybePop();
              },
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(eyebrow!.toUpperCase(), maxLines: 1, style: T.eyebrow(context).copyWith(color: onBand ? Colors.white.withValues(alpha: .8) : null)),
                  ),
                if (oneLine)
                  // Each line of the title (split on '\n') stays on one line.
                  for (final line in title.split('\n'))
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(line, maxLines: 1, style: T.h1(context).copyWith(color: fg)),
                    )
                else
                  Text(title, style: T.h1(context).copyWith(color: fg)),
                if (sub != null) Text(sub!, style: T.sm(context).copyWith(color: onBand ? Colors.white.withValues(alpha: .85) : context.c.muted)),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 6), a],
        ],
      ),
    );
  }
}

/// Marks a tab screen shown as a pushed page, so its header shows a back button.
class InPage extends InheritedWidget {
  const InPage({super.key, required super.child});
  @override
  bool updateShouldNotify(InPage old) => false;
}

/// Pushed page scaffold: colour-wash background, glass sticky header with back button,
/// title fades in on scroll (or [alwaysTitle]). Optional [footer] (buy bar / foot bar).
class HPage extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final Widget? footer;
  final bool alwaysTitle;
  final EdgeInsets padding;
  final Widget? hero; // full-bleed header content (no gutter) rendered under the header

  /// Pull-to-refresh, for pages showing data that can change on the server.
  final Future<void> Function()? onRefresh;
  const HPage({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.footer,
    this.alwaysTitle = true,
    this.padding = const EdgeInsets.symmetric(horizontal: kGutter),
    this.hero,
    this.onRefresh,
  });
  @override
  State<HPage> createState() => _HPageState();
}

class _HPageState extends State<HPage> {
  final _sc = ScrollController();
  bool _scrolled = false;
  // Stagger only the opening cascade; rows built later (scrolling) rise without delay.
  bool _settled = false;
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () => _settled = true);
    _sc.addListener(() {
      final s = _sc.offset > 36;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final top = MediaQuery.paddingOf(context).top;
    // Over a hero image the title only appears with the glass header, once scrolled.
    final showTitle = (widget.alwaysTitle && widget.hero == null) || _scrolled;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // Night: a faint ring of light in the top corner. Light: a soft blue wash.
          if (c.dark)
            const Positioned.fill(child: GlowSky(sky: false, swoosh: false, center: Alignment(1.25, -1.05), scale: .55, intensity: .55))
          else
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(center: const Alignment(1.1, -1.05), radius: 1.1, colors: [const Color(0xFF2F80FF).withValues(alpha: .14), const Color(0x002F80FF)]),
                ),
              ),
            ),
          RefreshIndicator(
            onRefresh: widget.onRefresh ?? () async {},
            notificationPredicate: (n) => widget.onRefresh != null && n.depth == 0,
            color: c.brand,
            edgeOffset: widget.hero == null ? top + 56 : 0,
            child: CustomScrollView(
              controller: _sc,
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: widget.hero == null ? top + 60 : 0)),
                if (widget.hero != null) SliverToBoxAdapter(child: widget.hero!),
                SliverPadding(
                  padding: widget.padding.copyWith(bottom: (widget.footer == null ? 40 : 120) + MediaQuery.paddingOf(context).bottom),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([for (var i = 0; i < widget.children.length; i++) Reveal(i: _settled ? 0 : i + 1, child: widget.children[i])]),
                  ),
                ),
              ],
            ),
          ),
          // glass header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: _scrolled ? 18 : 0, sigmaY: _scrolled ? 18 : 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.fromLTRB(8, top + 4, 8, 6),
                  decoration: BoxDecoration(
                    color: _scrolled ? c.glass : Colors.transparent,
                    border: Border(bottom: BorderSide(color: _scrolled ? c.line : Colors.transparent)),
                  ),
                  child: Row(
                    children: [
                      IconBtn(
                        'back',
                        raised: true,
                        onTap: () {
                          Sfx.back();
                          Navigator.of(context).maybePop();
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: showTitle ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: AnimatedSlide(
                            offset: showTitle ? Offset.zero : const Offset(0, .3),
                            duration: const Duration(milliseconds: 200),
                            child: Text(widget.title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: 44, child: widget.trailing),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.footer != null) Positioned(left: 0, right: 0, bottom: 0, child: FootBar(child: widget.footer!)),
        ],
      ),
    );
  }
}

/// Bottom action bar with rounded top and upward shadow.
class FootBar extends StatelessWidget {
  final Widget child;
  const FootBar({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(kGutter, 14, kGutter, 14 + MediaQuery.paddingOf(context).bottom),
    decoration: BoxDecoration(
      color: context.c.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      boxShadow: const [BoxShadow(color: Color(0x40002850), blurRadius: 30, spreadRadius: -12, offset: Offset(0, -10))],
    ),
    child: child,
  );
}

/// Column with uniform gap (prototype `display:grid;gap`).
class VStack extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  final CrossAxisAlignment cross;
  const VStack(this.children, {super.key, this.gap = 12, this.cross = CrossAxisAlignment.stretch});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: cross,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
    ],
  );
}

/// KPI tile; [hl] uses the sun gradient.
class Kpi extends StatelessWidget {
  final String label;
  final num value;
  final String Function(num)? format;
  final String? sub;
  final bool hl;
  final String? icon;
  const Kpi(this.label, this.value, {super.key, this.format, this.sub, this.hl = false, this.icon});
  @override
  Widget build(BuildContext context) {
    final fg = hl ? Colors.white : context.c.ink;
    return HCard(
      gradient: hl ? G.flame : null,
      shadow: hl ? const [BoxShadow(color: Color(0x802F80FF), blurRadius: 24, spreadRadius: -10, offset: Offset(0, 12))] : null,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Two-line label slot so tiles in a row keep equal heights on narrow phones.
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[HIcon(icon!, size: 16, color: hl ? Colors.white : context.c.brandText), const SizedBox(width: 6)],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.cap(context).copyWith(color: hl ? Colors.white.withValues(alpha: .9) : null, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // Scale long values down instead of wrapping them, in a fixed-height
          // slot so every tile keeps the same size.
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(38),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CountUp(
                value,
                format: format ?? (v) => v.round().toString(),
                style: T.h1(context).copyWith(color: fg, fontSize: 28),
              ),
            ),
          ),
          if (sub != null) Text(sub!, style: T.cap(context).copyWith(color: hl ? Colors.white.withValues(alpha: .85) : null)),
        ],
      ),
    );
  }
}

/// Summary numbers side by side, every tile the same height.
class KpiRow extends StatelessWidget {
  final List<Widget> kpis;
  const KpiRow(this.kpis, {super.key});
  @override
  // Every tile in the row is the same height, whatever its value.
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < kpis.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: kpis[i])],
      ],
    ),
  );
}
