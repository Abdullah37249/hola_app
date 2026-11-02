import 'package:flutter/material.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/booking_flow_view_model.dart';

/// Date strip (next 14 days) + free times grouped by part of day.
class SlotPicker extends StatelessWidget {
  final SlotPickerViewModel vm;
  const SlotPicker(this.vm, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final groups = vm.grouped;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 72 + MediaQuery.textScalerOf(context).scale(24),
        child: ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          children: [
            for (final d in vm.days)
              Padding(padding: const EdgeInsets.only(right: 8, top: 4, bottom: 8), child: _DayChip(vm: vm, d: d)),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (vm.isClosed(vm.day))
        Padding(padding: const EdgeInsets.only(top: 12), child: EmptyState(icon: 'clock', title: tr('Closed this day'), text: tr('Pick another day from the strip above.')))
      else if (groups.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: EmptyState(
            icon: 'cal',
            title: tr('Fully booked'),
            text: sameDay(vm.day, today) ? tr('No free times left today. Try another day.') : tr('No free times on {date}. Try another day.', {'date': dLabel(vm.day)}),
          ),
        )
      else
        for (final (label, slots) in groups) ...[
          Padding(padding: const EdgeInsets.only(top: 14, bottom: 10), child: Text(tr(label).toUpperCase(), style: T.eyebrow(context))),
          LayoutBuilder(builder: (context, k) {
            final w = (k.maxWidth - 3 * 8) / 4;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in slots)
                SizedBox(
                  width: w,
                  child: _TimeChip(
                    label: fmtTime(s.start).replaceAll(' ${tr('am')}', '').replaceAll(' ${tr('pm')}', ''),
                    on: vm.time == s.start,
                    onTap: () {
                      Sfx.tap();
                      vm.pickTime(s.start);
                    },
                  ),
                ),
            ]);
          }),
        ],
      if (vm.time != null) ...[
        const SizedBox(height: 14),
        HCard(
          color: c.brandSoft,
          shadow: const [],
          border: Border.all(color: c.brandLine),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            HIcon('check', size: 18, stroke: 2.4, color: c.brandText),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('{date} at {time}', {'date': dLabel(vm.time!), 'time': fmtTime(vm.time!)}), style: T.sm(context).copyWith(color: c.brandText, fontWeight: FontWeight.w600))),
          ]),
        ),
      ],
    ]);
  }
}

class _DayChip extends StatelessWidget {
  final SlotPickerViewModel vm;
  final DateTime d;
  const _DayChip({required this.vm, required this.d});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final on = sameDay(vm.day, d);
    final closed = vm.isClosed(d);
    final full = !closed && vm.isFull(d);
    final off = closed || full;
    return GestureDetector(
      onTap: () {
        Sfx.tap();
        vm.pickDay(d);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: kEase,
        width: 58,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: on ? c.brand : off ? c.bg2 : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? c.brand : c.line),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(sameDay(d, today) ? tr('Today') : days[weekday0(d)], style: T.cap(context).copyWith(color: on ? Colors.white.withValues(alpha: .85) : c.muted)),
          Text('${d.day}', style: T.h3(context).copyWith(color: on ? Colors.white : off ? c.subtle : c.ink)),
          Text(closed ? tr('Closed') : full ? tr('Full') : months[d.month - 1], style: T.cap(context).copyWith(fontSize: 11, color: on ? Colors.white.withValues(alpha: .85) : off ? c.subtle : c.muted)),
        ]),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _TimeChip({required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? c.brand : c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? c.brand : c.line),
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: T.ttl(context).copyWith(color: on ? Colors.white : c.ink))),
      ),
    );
  }
}
