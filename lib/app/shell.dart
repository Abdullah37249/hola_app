import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hola_professional/core/utils/sfx.dart';
import 'viewmodels/session_view_model.dart';
import 'package:hola_professional/shared/widgets/ui.dart';
import 'tabs.dart';

/// Role shell: tab views kept alive in an IndexedStack, plus the floating
/// glass tab bar with a sliding gradient pill (prototype v2).
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final Map<String, Widget> _built = {};

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
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: c.glass,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: c.surface.withValues(alpha: .6)),
            boxShadow: const [BoxShadow(color: Color(0x73002850), blurRadius: 40, spreadRadius: -14, offset: Offset(0, 18))],
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
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: G.btn,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Color(0xE6005BAC), blurRadius: 18, spreadRadius: -8, offset: Offset(0, 8))],
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
                                    child: HIcon(tabs[j].icon, size: 22, color: j == index ? Colors.white : c.muted),
                                  ),
                                  const SizedBox(height: 2),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: TextStyle(fontFamily: T.f, fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w600, color: j == index ? Colors.white : c.muted),
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
