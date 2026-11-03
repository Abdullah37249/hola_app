import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hola_professional/core/utils/sfx.dart';
import 'viewmodels/session_view_model.dart';
import 'package:hola_professional/shared/widgets/ui.dart';
import 'tabs.dart';
import '../domain/repositories/repositories.dart';
import '../features/profile/views/permissions_page.dart';

/// Role shell: tab views kept alive in an IndexedStack, plus the floating
/// glass tab bar with a sliding gradient pill (prototype v2).
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  final Map<String, Widget> _built = {};
  Timer? _poll;

  /// Bookings made or changed on the HOLA server (by customers, the salon or
  /// HOLA) arrive while the app is open: on start, every 20 seconds, and on resume.
  void _sync() {
    context.read<BookingRepository>().sync();
    context.read<EngagementRepository>().sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  // Pops up news that arrives while the app is open (e.g. "Booking confirmed").
  late final EngagementRepository _engage = context.read<EngagementRepository>();
  String? _lastNotice;

  String? _who;

  void _onData() {
    final latest = _engage.notifications().firstOrNull;
    final who = context.read<SessionViewModel>().account?.id;
    // Someone else signed in: their existing news isn't new.
    if (who != _who) {
      _who = who;
      _lastNotice = latest?.id;
      return;
    }
    if (latest == null || latest.id == _lastNotice) return;
    final fresh = _lastNotice != null && !latest.read;
    _lastNotice = latest.id;
    if (fresh && mounted) {
      Sfx.success();
      Fx.toast(tr(latest.title, latest.args), icon: latest.icon);
    }
  }

  @override
  void dispose() {
    _engage.changes.removeListener(_onData);
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastNotice = _engage.notifications().firstOrNull?.id ?? '';
    _who = context.read<SessionViewModel>().account?.id;
    _engage.changes.addListener(_onData);
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _sync());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
    // First time in: explain and ask for the phone permissions this role uses.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<SessionViewModel>();
      if (!mounted || !s.needsPermissionsIntro) return;
      s.permissionsIntroShown();
      Navigator.of(context).push(HolaRoute(const PermissionsPage(firstRun: true)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionViewModel>();
    final tabs = tabsFor[s.rk]!;
    final cur = tabs.indexWhere((t) => t.id == s.tab);
    final i = cur < 0 ? 0 : cur;
    // Lazily build tabs on first visit, keep them alive afterwards.
    _built.putIfAbsent(tabs[i].id, tabs[i].build);
    return PopScope(
      canPop: i == 0,
      onPopInvokedWithResult: (did, _) {
        if (!did) s.setTab(tabs[0].id);
      },
      child: Scaffold(
        backgroundColor: context.c.bg,
        extendBody: true,
        body: Stack(
          children: [
            _TabSwap(
              index: i,
              child: IndexedStack(index: i, children: [for (final t in tabs) _built[t.id] ?? const SizedBox()]),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 14 + MediaQuery.paddingOf(context).bottom,
              child: _TabBar(
                tabs: tabs,
                index: i,
                onTap: (id) {
                  if (id != tabs[i].id) Sfx.tap();
                  s.setTab(id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades and lifts the tab content in whenever [index] changes; the stack
/// itself is untouched, so each tab keeps its state and scroll position.
class _TabSwap extends StatefulWidget {
  final int index;
  final Widget child;
  const _TabSwap({required this.index, required this.child});
  @override
  State<_TabSwap> createState() => _TabSwapState();
}

class _TabSwapState extends State<_TabSwap> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: kEase);

  @override
  void didUpdateWidget(_TabSwap old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: .35, end: 1.0).animate(_a),
    child: SlideTransition(
      position: Tween(begin: const Offset(0, .015), end: Offset.zero).animate(_a),
      child: widget.child,
    ),
  );
}

class _TabBar extends StatelessWidget {
  final List<TabDef> tabs;
  final int index;
  final ValueChanged<String> onTap;
  const _TabBar({required this.tabs, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: c.glass,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.dark ? const Color(0xFF1F4A8A) : c.surface.withValues(alpha: .6)),
            boxShadow: [BoxShadow(color: c.dark ? const Color(0x552F80FF) : const Color(0x73002850), blurRadius: 40, spreadRadius: -14, offset: const Offset(0, 18))],
          ),
          child: LayoutBuilder(
            builder: (context, k) {
              final w = k.maxWidth / tabs.length;
              return SizedBox(
                height: 54,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 450),
                      curve: kSpring,
                      left: w * index,
                      top: 0,
                      bottom: 0,
                      width: w,
                      // Night: the poster's white pill. Light: brand blue.
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: c.dark ? null : G.btn,
                          color: c.dark ? Colors.white : null,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [BoxShadow(color: c.dark ? const Color(0x996FB0FF) : const Color(0xE62F80FF), blurRadius: 20, spreadRadius: -6, offset: const Offset(0, 4))],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var j = 0; j < tabs.length; j++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onTap(tabs[j].id),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedScale(
                                    scale: j == index ? 1.06 : 1,
                                    duration: const Duration(milliseconds: 300),
                                    curve: kSpring,
                                    child: HIcon(tabs[j].icon, size: 22, color: j == index ? (c.dark ? c.night : Colors.white) : c.muted),
                                  ),
                                  const SizedBox(height: 2),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: TextStyle(
                                      fontFamily: T.f,
                                      fontSize: 11,
                                      height: 14 / 11,
                                      fontWeight: j == index ? FontWeight.w700 : FontWeight.w600,
                                      color: j == index ? (c.dark ? c.night : Colors.white) : c.muted,
                                    ),
                                    child: Text(tr(tabs[j].label), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ],
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
        ),
      ),
    );
  }
}
