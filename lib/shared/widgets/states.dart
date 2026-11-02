import 'package:flutter/material.dart';

import 'package:hola_professional/core/utils/network_status.dart';
import 'ui.dart';

// Loading, failure and offline states for data that comes from the network.
// On-device data loads instantly, so these only appear once screens read from
// the HOLA backend.

/// Soft light sweeping across its child's grey shapes while content loads.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = SkeletonBox.tone(context), hi = context.c.dark ? context.c.subtle.withValues(alpha: .5) : context.c.surface2;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final x = -1.5 + 3 * Curves.easeInOut.transform(_c.value);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) => LinearGradient(begin: Alignment(x - .6, -.3), end: Alignment(x + .6, .3), colors: [base, hi, base], stops: const [.2, .5, .8]).createShader(r),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A grey placeholder shape; wrap a group of them in [Shimmer].
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  /// Placeholder grey: page tint in light mode, the divider tone in dark (bg2 vanishes on dark cards).
  static Color tone(BuildContext context) => context.c.dark ? context.c.line : context.c.bg2;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: tone(context), borderRadius: BorderRadius.circular(radius)),
  );
}

/// Placeholder list shaped like the app's row cards (thumbnail, two lines).
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 4});
  @override
  Widget build(BuildContext context) => Semantics(
    label: tr('Loading'),
    child: VStack(gap: 12, [
      for (var i = 0; i < count; i++)
        HCard(
          // Shimmer only the shapes, not the card behind them.
          child: Shimmer(
            child: Row(children: [
              const SkeletonBox(width: 52, height: 52, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SkeletonBox(width: i.isEven ? 160 : 120, height: 16),
                  const SizedBox(height: 8),
                  SkeletonBox(width: i.isEven ? 110 : 150, height: 12),
                ]),
              ),
            ]),
          ),
        ),
    ]),
  );
}

/// Shown in place of content that failed to load, with a Retry button.
class LoadError extends StatelessWidget {
  final String? message;
  final Future<void> Function() onRetry;
  const LoadError({super.key, this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => HCard(
    child: EmptyState(
      icon: 'wifi',
      title: tr("Couldn't load"),
      text: message ?? tr('Check your connection and try again.'),
      cta: HButton(tr('Retry'), icon: 'sync', kind: BtnKind.secondary, small: true, onTap: onRetry),
    ),
  );
}

/// Picks what a data screen shows: placeholders on the first load, an error
/// card if that load failed, otherwise the content. Once content exists it
/// stays on screen while refreshing, so lists never blank out.
class AsyncBody extends StatelessWidget {
  final bool loading, hasData;
  final Object? error;
  final Future<void> Function() onRetry;
  final Widget Function(BuildContext) builder;
  final int skeletons;
  const AsyncBody({super.key, required this.loading, required this.hasData, required this.error, required this.onRetry, required this.builder, this.skeletons = 4});
  @override
  Widget build(BuildContext context) {
    final state = hasData || (!loading && error == null)
        ? 'data'
        : loading
        ? 'loading'
        : 'error';
    final body = switch (state) {
      'loading' => SkeletonList(count: skeletons),
      'error' => LoadError(onRetry: onRetry),
      _ => builder(context),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(state), child: body),
    );
  }
}

/// Slim banner under the status bar while [NetworkStatus] reports no connection.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: NetworkStatus.online,
    builder: (context, online, _) => IgnorePointer(
      child: AnimatedSlide(
        offset: online ? const Offset(0, -1.5) : Offset.zero,
        duration: const Duration(milliseconds: 350),
        curve: kEase,
        child: AnimatedOpacity(
          opacity: online ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF13111C),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 6))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HIcon('wifi', size: 16, color: Color(0xFFFFB15C)),
                  const SizedBox(width: 8),
                  Text(tr("You're offline. Check your connection."),
                    style: T.cap(context).copyWith(color: Colors.white, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
