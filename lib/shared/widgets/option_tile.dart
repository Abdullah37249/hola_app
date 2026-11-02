import 'package:flutter/material.dart';

import 'ui.dart';

/// Radio-style option card (prototype `.opt`).
class OptionTile extends StatelessWidget {
  final String? icon;
  final String title;
  final String? sub;
  final bool on;
  final VoidCallback onTap;
  final Widget? leading, trailing;
  const OptionTile({super.key, this.icon, required this.title, this.sub, required this.on, required this.onTap, this.leading, this.trailing});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tap(
      onTap: onTap,
      scale: .98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? c.brand : Colors.transparent, width: 2),
          boxShadow: on ? c.liftHi : c.lift,
        ),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)] else if (icon != null) ...[
            Container(width: 40, height: 40, decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle), alignment: Alignment.center, child: HIcon(icon!, size: 20, color: c.brandText)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.ttl(context)),
              if (sub != null) Text(sub!, style: T.sm(context).copyWith(color: c.muted)),
            ]),
          ),
          trailing ??
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? c.brand : c.line, width: on ? 7 : 2)),
              ),
        ]),
      ),
    );
  }
}
