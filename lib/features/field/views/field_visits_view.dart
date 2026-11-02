import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/field_view_models.dart';
import '../widgets/field_widgets.dart';
import 'visit_view.dart';

class FieldVisits extends StatelessWidget {
  const FieldVisits({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => FieldVisitsViewModel(salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), field: c.read<FieldRepository>()),
        child: const _Body(),
      );
}

class _Body extends StatelessWidget {
  const _Body();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FieldVisitsViewModel>();
    final list = vm.selected;
    final week = vm.week;
    return BandView(role: 'field', children: [
      ...staggered([
        TopHead(
          title: tr('Visits'),
          sub: '${months[week.first.month - 1]} ${week.first.day} – ${months[week.last.month - 1]} ${week.last.day}',
          actions: [
            IconBtn('back', onBand: true, onTap: () => vm.shiftWeek(-1)),
            IconBtn('chev', onBand: true, onTap: () => vm.shiftWeek(1)),
          ],
        ),
        const SizedBox(height: 14),
        Row(children: [
          for (final d in week) ...[
            if (d != week.first) const SizedBox(width: 6),
            Expanded(child: _DayCell(day: d, on: sameDay(d, vm.day), count: vm.visitsOn(d).length, onTap: () => vm.pickDay(d))),
          ],
        ]),
      ]),
      const BandMark(),
      ...staggered([
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Text(dayLabel(vm.day, today), style: T.h3(context))),
          if (!vm.day.isBefore(today) && list.isNotEmpty) HButton(tr('Plan visit'), icon: 'plus', small: true, onTap: () => planVisitSheet(context, day: vm.day)),
        ]),
        const SizedBox(height: 12),
      ], 2),
      if (list.isEmpty)
        HCard(
          child: EmptyState(
            icon: 'pin',
            title: vm.day.isBefore(today) ? tr('No visits that day') : tr('No visits planned'),
            text: vm.day.isBefore(today) ? tr('Pick another day to see past visits.') : tr('Plan a visit, then check in when you arrive. Your check-in time is saved on the visit.'),
            cta: vm.day.isBefore(today) ? null : HButton(tr('Plan a visit'), icon: 'plus', small: true, onTap: () => planVisitSheet(context, day: vm.day)),
          ),
        )
      else
        Reveal(i: 3, child: CardList([for (final v in list) VisitTile(visit: v, salon: vm.salonName(v.salonId), place: vm.place(v.salonId), onTap: () => pushPage(context, VisitPage(id: v.id)))])),
      if (vm.upcoming.isNotEmpty) ...[
        const SizedBox(height: 28),
        Reveal(i: 4, child: SecHead(tr('Coming up'))),
        const SizedBox(height: 12),
        Reveal(i: 5, child: CardList([for (final v in vm.upcoming) VisitTile(visit: v, salon: vm.salonName(v.salonId), place: vm.place(v.salonId), showDate: true, onTap: () => pushPage(context, VisitPage(id: v.id)))])),
      ],
      const SizedBox(height: 16),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool on;
  final int count;
  final VoidCallback onTap;
  const _DayCell({required this.day, required this.on, required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isToday = sameDay(day, today);
    return Tap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: kEase,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: on ? G.btn : null,
          color: on ? null : c.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: on ? const [BoxShadow(color: Color(0x66005BAC), blurRadius: 16, spreadRadius: -8, offset: Offset(0, 8))] : c.lift,
        ),
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(isToday ? tr('Today') : tr(weekdaysMon[day.weekday - 1]), style: T.cap(context).copyWith(color: on ? Colors.white.withValues(alpha: .85) : null))),
          FittedBox(fit: BoxFit.scaleDown, child: Text('${day.day}', style: T.h3(context).copyWith(color: on ? Colors.white : null))),
          const SizedBox(height: 2),
          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: count == 0 ? Colors.transparent : on ? Colors.white : c.brand)),
        ]),
      ),
    );
  }
}
