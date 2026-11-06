import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../trade/trade.dart';
import '../viewmodels/field_view_models.dart';
import '../widgets/field_widgets.dart';

class FieldOrders extends StatelessWidget {
  const FieldOrders({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => FieldOrdersViewModel(salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), trade: c.read<TradeRepository>()),
    child: const _Body(),
  );
}

class _Body extends StatelessWidget {
  const _Body();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FieldOrdersViewModel>();
    final list = vm.results;
    final pending = vm.pendingHandovers;
    return BandView(
      role: 'field',
      children: [
        ...staggered([
          TopHead(
            title: tr('Orders'),
            sub: vm.all.isEmpty ? tr('Trade orders from salons') : tr('{orders} to approve · {n} to dispatch', {'orders': plural(vm.count('approve'), 'order'), 'n': vm.count('dispatch')}),
            actions: [
              HButton(
                tr('New'),
                icon: 'plus',
                small: true,
                kind: BtnKind.white,
                onTap: () async {
                  final active = context.read<SalonRepository>().allSalons().where((s) => s.isActive).toList();
                  final id = await pickSalon(context, title: tr('Order for which salon?'), salons: active, note: tr('Only HOLA-verified salons can order products.'));
                  if (id != null && context.mounted) pushPage(context, NewOrderPage(salonId: id));
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          KpiStrip([Kpi(tr('This week'), vm.thisWeek, icon: 'box'), Kpi(tr('Open value'), vm.openValue, format: shortNum, icon: 'cash'), Kpi(tr('In delivery'), vm.count('delivery'), icon: 'truck')]),
          const SizedBox(height: 16),
        ]),
        if (pending.isNotEmpty) ...[
          Reveal(i: 3, child: SecHead(tr('Cash to confirm'))),
          const SizedBox(height: 12),
          Reveal(
            i: 4,
            child: CardList([for (final h in pending) _HandoverRow(h: h, vm: vm)]),
          ),
          const SizedBox(height: 24),
        ],
        if (vm.all.isNotEmpty) ...[
          Reveal(
            i: 5,
            child: ChipRow(
              children: [
                for (final f in FieldOrdersViewModel.filters)
                  HChip('${f.$2}${f.$1 != 'all' && vm.count(f.$1) > 0 ? ' · ${vm.count(f.$1)}' : ''}', on: vm.filter == f.$1, onTap: () => vm.setFilter(f.$1)),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (vm.all.isEmpty)
          HCard(
            child: EmptyState(icon: 'box', title: tr('No orders yet'), text: tr('Orders salons place, and ones you take on visits, appear here for approval and dispatch.')),
          )
        else if (list.isEmpty)
          EmptyState(icon: 'check', title: tr('All clear'), text: tr('No orders in this list right now.'))
        else
          ...staggered([
            for (final o in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OrderCard(
                  order: o,
                  showSalon: true,
                  onTap: () => pushPage(context, OrderDetailPage(id: o.id)),
                ),
              ),
          ], 6),
        if (vm.recentConfirmed.isNotEmpty) ...[
          const SizedBox(height: 18),
          SecHead(tr('Recently confirmed cash')),
          const SizedBox(height: 12),
          CardList([
            for (final h in vm.recentConfirmed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vm.personName(h.riderId), style: T.ttl(context)),
                          Text(
                            tr('{deliveries} · confirmed {when}', {'deliveries': plural(h.orderIds.length, 'delivery', 'deliveries'), 'when': h.confirmedAt == null ? '' : ago(h.confirmedAt!, now())}),
                            style: T.cap(context),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      rs(h.amount),
                      style: T.sm(context).copyWith(color: context.c.ink, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ]),
        ],
      ],
    );
  }
}

class _HandoverRow extends StatelessWidget {
  final CashHandover h;
  final FieldOrdersViewModel vm;
  const _HandoverRow({required this.h, required this.vm});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Avatar(vm.personName(h.riderId), size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rs(h.amount), style: T.ttl(context)),
              Text('${vm.personName(h.riderId)} · ${plural(h.orderIds.length, 'delivery', 'deliveries')} · ${ago(h.at, now())}', maxLines: 2, overflow: TextOverflow.ellipsis, style: T.cap(context)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        HButton(
          tr('Confirm'),
          small: true,
          kind: BtnKind.ok,
          onTap: () async {
            if (await confirmSheet(
              context,
              title: tr('Confirm {amount} received?', {'amount': rs(h.amount)}),
              body: tr('Only confirm once you have counted the cash from {name}.', {'name': vm.personName(h.riderId)}),
              confirm: tr('Cash received'),
            )) {
              await attempt(() => vm.confirmHandover(h.id), success: tr('Cash confirmed'), icon: 'cash');
            }
          },
        ),
      ],
    ),
  );
}
