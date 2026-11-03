import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../../notifications/notifications.dart';
import '../../trade/trade.dart';
import '../viewmodels/field_view_models.dart';
import '../widgets/field_widgets.dart';
import 'report_views.dart';
import 'salon_record_view.dart';
import 'visit_view.dart';

class FieldToday extends StatelessWidget {
  const FieldToday({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => FieldTodayViewModel(salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), field: c.read<FieldRepository>(), trade: c.read<TradeRepository>()),
    child: const _Body(),
  );
}

class _Body extends StatelessWidget {
  const _Body();

  String _greeting() {
    final h = now().hour;
    return h < 12
        ? tr('Good morning')
        : h < 17
        ? tr('Good afternoon')
        : tr('Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FieldTodayViewModel>();
    final c = context.c;
    final me = vm.me;
    final next = vm.nextVisit;
    final session = context.read<SessionViewModel>();

    // One row per kind of work, with how many are waiting. A single item opens
    // directly; several open the tab that lists them.
    final rows = <(String, String, String, int, VoidCallback)>[
      if (vm.toVerify.isNotEmpty)
        (
          'shield',
          tr('Verify salons'),
          vm.toVerify.length == 1 ? vm.toVerify.first.name : tr('Adds the Verified badge and unlocks orders'),
          vm.toVerify.length,
          () => vm.toVerify.length == 1 ? pushPage(context, SalonRecordPage(id: vm.toVerify.first.id)) : session.setTab('salons'),
        ),
      if (vm.toApprove.isNotEmpty)
        (
          'box',
          tr('Approve orders'),
          vm.toApprove.length == 1 ? '${vm.toApprove.first.code} · ${vm.salonName(vm.toApprove.first.salonId)}' : tr('Placed by salons, waiting for you'),
          vm.toApprove.length,
          () => vm.toApprove.length == 1 ? pushPage(context, OrderDetailPage(id: vm.toApprove.first.id)) : session.setTab('orders'),
        ),
      if (vm.toDispatch.isNotEmpty)
        (
          'truck',
          tr('Assign a rider'),
          vm.toDispatch.length == 1 ? '${vm.toDispatch.first.code} · ${vm.salonName(vm.toDispatch.first.salonId)}' : tr('Approved orders ready to go out'),
          vm.toDispatch.length,
          () => vm.toDispatch.length == 1 ? pushPage(context, OrderDetailPage(id: vm.toDispatch.first.id)) : session.setTab('orders'),
        ),
      if (vm.handoversToConfirm.isNotEmpty)
        (
          'cash',
          tr('Confirm cash'),
          vm.handoversToConfirm.length == 1
              ? tr('{amount} from {name}', {'amount': rs(vm.handoversToConfirm.first.amount), 'name': vm.personName(vm.handoversToConfirm.first.riderId)})
              : tr('Riders handed over cash'),
          vm.handoversToConfirm.length,
          () => session.setTab('orders'),
        ),
    ];

    return BandView(
      role: 'field',
      children: [
        ...staggered([
          TopHead(eyebrow: dLabel(today), title: tr('{greeting}, {name}', {'greeting': _greeting(), 'name': me?.firstName ?? ''}), actions: const [NotificationBell()]),
          const SizedBox(height: 16),
          HCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ProgressRing(done: vm.visitsDone, total: vm.todays.length, size: 84),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        vm.todays.isEmpty
                            ? tr('No visits planned')
                            : vm.visitsDone == vm.todays.length
                            ? tr('All visits done')
                            : tr('{visits} to go', {'visits': plural(vm.todays.length - vm.visitsDone, 'visit')}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.h3(context),
                      ),
                      const SizedBox(height: 8),
                      _Line(tr('Booked today'), rs(vm.bookedToday)),
                      const SizedBox(height: 4),
                      _Line(tr('Daily report'), vm.reportDone ? tr('Submitted') : tr('Not yet'), color: vm.reportDone ? c.ok : null),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]),
        const BandMark(),
        ...staggered([
          const SizedBox(height: 24),
          SecHead(tr('Next visit')),
          const SizedBox(height: 12),
          if (next == null)
            HCard(
              child: EmptyState(
                icon: 'pin',
                title: vm.todays.isEmpty ? tr('Nothing planned today') : tr('Every visit today is done'),
                text: vm.todays.isEmpty ? tr('Plan a salon visit to start your day.') : tr('Nice work. Submit your daily report when you\'re ready.'),
                cta: vm.todays.isEmpty
                    ? HButton(tr('Plan a visit'), icon: 'plus', small: true, onTap: () => planVisitSheet(context))
                    : HButton(tr('Daily report'), icon: 'clip', small: true, kind: BtnKind.secondary, onTap: () => pushPage(context, const DailyReportPage())),
              ),
            )
          else
            _NextVisitCard(vm: vm),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 24),
            SecHead(tr('Needs attention')),
            const SizedBox(height: 12),
            Group(
              children: [for (final r in rows) MRow(icon: r.$1, title: r.$2, sub: r.$3, trailing: CountPill(r.$4), onTap: r.$5)],
            ),
          ],
          const SizedBox(height: 24),
          SecHead(tr('Shortcuts')),
          const SizedBox(height: 12),
          _QuickActions(vm: vm),
        ], 2),
      ],
    );
  }
}

/// "Label ........ value" on one line that never wraps the value.
class _Line extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _Line(this.label, this.value, {this.color});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.sm(context).copyWith(color: context.c.muted),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        value,
        maxLines: 1,
        style: T.sm(context).copyWith(color: color ?? context.c.ink, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _NextVisitCard extends StatelessWidget {
  final FieldTodayViewModel vm;
  const _NextVisitCard({required this.vm});
  @override
  Widget build(BuildContext context) {
    final v = vm.nextVisit!;
    final s = vm.salon(v.salonId);
    final c = context.c;
    final onVisit = v.status == 'CHECKED_IN';
    return HCard(
      padding: EdgeInsets.zero,
      onTap: () => pushPage(context, VisitPage(id: v.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SalonArt(s?.palette ?? 0, photo: s?.cover, height: 96, radius: 0, name: s?.name),
          Padding(
            padding: const EdgeInsets.all(16),
            child: VStack(gap: 12, [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vm.salonName(v.salonId), style: T.h3(context)),
                        Text([vm.place(v.salonId), fmtTime(v.plannedFor)].where((x) => x.isNotEmpty).join(' · '), style: T.sm(context).copyWith(color: c.muted)),
                        Text(tr(v.purpose), style: T.sm(context)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ToneBadge(onVisit ? tr('On visit') : tr('Planned'), tone: onVisit ? 'info' : 'mute', live: onVisit),
                ],
              ),
              HButton(
                onVisit ? tr('Write visit report') : tr('Check in'),
                icon: onVisit ? 'edit' : 'pin',
                block: true,
                onTap: () => pushPage(context, VisitPage(id: v.id)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final FieldTodayViewModel vm;
  const _QuickActions({required this.vm});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final items = <(String, String, VoidCallback)>[
      ('pin', tr('Plan visit'), () => planVisitSheet(context)),
      (
        'box',
        tr('New order'),
        () async {
          final id = await pickSalon(context, title: tr('Order for which salon?'), salons: vm.orderable, note: tr('Only HOLA-verified salons can order products.'));
          if (id != null && context.mounted) pushPage(context, NewOrderPage(salonId: id));
        },
      ),
      ('bag', tr('Products'), () => pushPage(context, const ProductsAdminPage())),
      ('clip', tr('Daily report'), () => pushPage(context, const DailyReportPage())),
    ];
    return VStack(gap: 10, [
      for (var r = 0; r < items.length; r += 2)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = r; i < r + 2 && i < items.length; i++) ...[
                if (i > r) const SizedBox(width: 10),
                Expanded(
                  child: HCard(
                    onTap: items[i].$3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconTile(items[i].$1),
                        const SizedBox(height: 12),
                        Text(
                          items[i].$2,
                          style: T.sm(context).copyWith(color: c.ink, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    ]);
  }
}
