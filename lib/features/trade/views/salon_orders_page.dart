import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/trade_view_models.dart';
import '../widgets/trade_widgets.dart';
import 'new_order_page.dart';
import 'order_detail_page.dart';
import 'statement_page.dart';

/// A salon's HOLA trade orders, with credit at a glance and "New order".
class SalonOrdersPage extends StatelessWidget {
  const SalonOrdersPage({super.key, required this.salonId});
  final String salonId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => SalonOrdersViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), salonId),
        child: const _Body(),
      );
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonOrdersViewModel>();
    final s = vm.salon;
    final c = context.c;
    if (s == null) return HPage(title: tr('Product orders'), children: [EmptyState(icon: 'store', title: tr('Salon not found'), text: tr('It may have been removed.'))]);
    final orders = vm.orders;
    return HPage(
      title: tr('Product orders'),
      footer: s.isActive ? HButton(tr('New order'), icon: 'plus', block: true, onTap: () => pushPage(context, NewOrderPage(salonId: s.id))) : null,
      children: [
        ...staggered([
          Text(tr('Product orders'), style: T.h1(context)),
          Text(tr('HOLA professional products for {salon}', {'salon': s.name}), style: T.sub(context)),
          const SizedBox(height: 16),
          Tap(onTap: () => pushPage(context, StatementPage(salonId: s.id)), child: CreditCard(salonId: s.id)),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => pushPage(context, StatementPage(salonId: s.id)), child: Text(tr('View statement'), style: T.link(context))),
          ),
          if (!s.isActive)
            HCard(
              color: c.accentSoft,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                HIcon('alert', size: 20, color: c.accentInk),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('Product orders open once a HOLA sales officer verifies your salon. Customers can already find and book you.'), style: T.sm(context).copyWith(color: c.accentInk))),
              ]),
            ),
          const SizedBox(height: 12),
          Seg(
            opts: [('open', '${tr('Open')}${vm.openCount > 0 ? ' · ${vm.openCount}' : ''}'), ('delivered', tr('Delivered')), ('all', tr('All'))],
            value: vm.filter.name,
            onChanged: (v) => vm.setFilter(OrderFilter.values.byName(v)),
          ),
          const SizedBox(height: 16),
        ]),
        if (orders.isEmpty)
          EmptyState(
            icon: 'box',
            title: vm.all.isEmpty ? tr('No orders yet') : tr('Nothing here'),
            text: vm.all.isEmpty
                ? (s.isActive ? tr('Order colour, care and styling products from HOLA. Delivered to your salon.') : tr('Once HOLA verifies your salon you can order products here.'))
                : vm.filter == OrderFilter.open ? tr('No open orders right now.') : tr('No delivered orders right now.'),
            cta: vm.all.isEmpty && s.isActive ? HButton(tr('Browse products'), kind: BtnKind.secondary, small: true, onTap: () => pushPage(context, NewOrderPage(salonId: s.id))) : null,
          )
        else
          ...staggered([
            for (final o in orders) Padding(padding: const EdgeInsets.only(bottom: 12), child: OrderCard(order: o, onTap: () => pushPage(context, OrderDetailPage(id: o.id)))),
          ], 6),
      ],
    );
  }
}

/// Status filter helper for other features that list orders.
bool isOpenOrder(TradeOrder o) => OrderStatus.open.contains(o.status);
