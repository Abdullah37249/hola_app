import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/field_view_models.dart';
import '../widgets/field_widgets.dart';

/// Figures worked out from the officer's own visits and orders.
class PerformancePage extends StatelessWidget {
  const PerformancePage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => PerformanceViewModel(salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), field: c.read<FieldRepository>(), trade: c.read<TradeRepository>()),
    child: const _PerfBody(),
  );
}

class _PerfBody extends StatelessWidget {
  const _PerfBody();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PerformanceViewModel>();
    final c = context.c;
    final outcomes = vm.outcomeCounts;
    final maxOutcome = outcomes.values.fold(0, (a, b) => a > b ? a : b);
    return HPage(
      title: tr('My performance'),
      children: staggered([
        Seg(opts: [('week', tr('This week')), ('month', tr('This month'))], value: vm.period, onChanged: vm.setPeriod),
        const SizedBox(height: 16),
        HCard(
          child: Row(
            children: [
              ProgressRing(done: vm.visitsDone, total: vm.visitsPlanned),
              const SizedBox(width: 16),
              Expanded(
                child: VStack(gap: 6, [
                  Text(vm.visitsPlanned == 0 ? tr('No visits planned yet') : tr('{pct}% of planned visits done', {'pct': (vm.completion * 100).round()}), style: T.ttl(context)),
                  KV(tr('Salons visited'), '${vm.salonsVisited}'),
                  KV(tr('Since'), dLabel(vm.from)),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KpiStrip([
          Kpi(tr('Orders taken'), vm.ordersCount, hl: true, icon: 'box'),
          Kpi(tr('Order value'), vm.ordersValue, format: shortNum, icon: 'cash'),
          Kpi(tr('Verified salons'), vm.activeSalons, sub: tr('of {n} on HOLA', {'n': vm.totalSalons}), icon: 'shield'),
        ]),
        const SizedBox(height: 24),
        SecHead(tr('Visit outcomes')),
        const SizedBox(height: 12),
        if (outcomes.isEmpty)
          HCard(
            child: Text(tr('Complete visits to see what they led to.'), style: T.sm(context).copyWith(color: c.muted)),
          )
        else
          HCard(
            child: VStack(gap: 12, [
              for (final (k, label) in visitOutcomes)
                if (outcomes[k] != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(tr(label), style: T.sm(context).copyWith(color: c.ink)),
                          ),
                          Text(
                            '${outcomes[k]}',
                            style: T.sm(context).copyWith(fontWeight: FontWeight.w600, color: c.ink),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      HProgress(outcomes[k]! / maxOutcome, height: 6),
                    ],
                  ),
            ]),
          ),
        const SizedBox(height: 12),
        Text(tr('Worked out from the visits and orders you recorded in the app.'), style: T.cap(context)),
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// Today's figures (computed) plus notes; submitted once per day.
class DailyReportPage extends StatelessWidget {
  const DailyReportPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => DailyReportViewModel(salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), field: c.read<FieldRepository>(), trade: c.read<TradeRepository>()),
    child: const _ReportBody(),
  );
}

class _ReportBody extends StatelessWidget {
  const _ReportBody();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DailyReportViewModel>();
    final c = context.c;
    final r = vm.submitted;
    final open = vm.todays.where((v) => v.status != VisitStatus.completed).length;
    return HPage(
      title: tr('Daily report'),
      footer: r != null
          ? null
          : HButton(
              tr('Submit report'),
              icon: 'check',
              block: true,
              onTap: () async {
                if (open > 0 &&
                    !await confirmSheet(
                      context,
                      title: open == 1 ? tr('Submit with {n} visit open?', {'n': open}) : tr('Submit with {n} visits open?', {'n': open}),
                      body: tr('Visits you haven\'t completed will count as not done.'),
                      confirm: tr('Submit anyway'),
                    )) {
                  return;
                }
                await attempt(vm.submit, success: tr('Report submitted'), icon: 'clip');
              },
            ),
      children: staggered([
        Text(dLabel(today).toUpperCase(), style: T.eyebrow(context)),
        const SizedBox(height: 10),
        KpiStrip([
          Kpi(tr('Visits done'), r?.visitsDone ?? vm.visitsDone, sub: tr('of {n}', {'n': r?.visitsPlanned ?? vm.todays.length}), hl: true, icon: 'pin'),
          Kpi(tr('Orders'), r?.ordersCount ?? vm.ordersToday.length, icon: 'box'),
          Kpi(tr('Value'), r?.ordersValue ?? vm.ordersValue, format: shortNum, icon: 'cash'),
        ]),
        const SizedBox(height: 24),
        if (vm.todays.isNotEmpty) ...[
          SecHead(tr("Today's visits")),
          const SizedBox(height: 12),
          CardList([
            for (final v in vm.todays)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    HIcon(v.status == VisitStatus.completed ? 'check' : 'clock', size: 18, color: v.status == VisitStatus.completed ? c.ok : c.subtle),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        vm.salonName(v.salonId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.sm(context).copyWith(color: c.ink),
                      ),
                    ),
                    Text(fmtTime(v.plannedFor), style: T.cap(context)),
                  ],
                ),
              ),
          ]),
          const SizedBox(height: 24),
        ],
        if (r != null)
          HCard(
            color: c.okSoft,
            child: VStack(gap: 6, [
              Row(
                children: [
                  HIcon('check', size: 18, color: c.ok),
                  const SizedBox(width: 8),
                  Text(tr('Submitted at {time}', {'time': fmtTime(r.submittedAt)}), style: T.ttl(context)),
                ],
              ),
              if (r.notes.isNotEmpty) Text(r.notes, style: T.sm(context)),
            ]),
          )
        else
          HField(label: tr('Notes for your manager'), hint: tr('Highlights, problems, what you need'), multiline: true, onChanged: (t) => vm.notes = t),
        if (vm.past.isNotEmpty) ...[
          const SizedBox(height: 24),
          SecHead(tr('Past reports')),
          const SizedBox(height: 12),
          CardList([
            for (final p in vm.past.take(14))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dLabel(p.day), style: T.ttl(context)),
                          Text(
                            tr('{done}/{planned} visits · {orders} · {value}', {
                              'done': p.visitsDone,
                              'planned': p.visitsPlanned,
                              'orders': plural(p.ordersCount, 'order'),
                              'value': rsShort(p.ordersValue),
                            }),
                            style: T.cap(context),
                          ),
                          if (p.notes.isNotEmpty)
                            Text(
                              p.notes,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: T.cap(context).copyWith(color: c.body),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ]),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}
