import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
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
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => SalonOrdersViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), salonId), child: const _Body());
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonOrdersViewModel>();
    final s = vm.salon;
    if (s == null) {
      return HPage(
        title: tr('Product orders'),
        children: [EmptyState(icon: 'store', title: tr('Salon not found'), text: tr('It may have been removed.'))],
      );
    }
    return HPage(
      title: tr('Product orders'),
      footer: s.isActive
          ? HButton(
              tr('New order'),
              icon: 'plus',
              block: true,
              onTap: () => pushPage(context, NewOrderPage(salonId: s.id)),
            )
          : null,
      children: [
        ...staggered([
          Text(tr('Product orders'), style: T.h1(context)),
          Text(tr('HOLA professional products for {salon}', {'salon': s.name}), style: T.sub(context)),
          const SizedBox(height: 16),
        ]),
        ..._orders(context, vm, s),
      ],
    );
  }
}

/// The salon's Products tab: credit across the header, then a switch between
/// ordering HOLA products (added straight from the list) and the salon's orders.
class SalonProductsTab extends StatelessWidget {
  const SalonProductsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final salonId = context.read<AuthRepository>().current?.salonId ?? '';
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (c) => SalonOrdersViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), salonId)),
        ChangeNotifierProvider(create: (c) => NewOrderViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), salonId)),
      ],
      child: const _ProductsTabBody(),
    );
  }
}

class _ProductsTabBody extends StatefulWidget {
  const _ProductsTabBody();
  @override
  State<_ProductsTabBody> createState() => _ProductsTabBodyState();
}

class _ProductsTabBodyState extends State<_ProductsTabBody> {
  var _ordering = true;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonOrdersViewModel>();
    final cart = context.watch<NewOrderViewModel>();
    final s = vm.salon;
    if (s == null) return const SizedBox();
    final c = context.c;
    final products = cart.allProducts;
    final orders = vm.all;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        BandView(
          role: 'salon',
          onRefresh: () {
            final trade = context.read<TradeRepository>();
            return Future.wait([trade.syncCatalogue(), trade.syncOrders(s.id)]);
          },
          children: [
            ...staggered([
              TopHead(title: tr('Products'), sub: tr('HOLA professional products for {salon}', {'salon': s.name})),
              const SizedBox(height: 18),
            ]),
            // Credit sits across the header's edge.
            BandMark(
              child: Reveal(
                i: 1,
                child: Tap(
                  onTap: () => pushPage(context, StatementPage(salonId: s.id)),
                  child: CreditCard(salonId: s.id),
                ),
              ),
            ),
            const SizedBox(height: 18),
            ...staggered([
              Seg(
                opts: [('order', tr('Order products')), ('mine', '${tr('My orders')}${vm.openCount > 0 ? ' · ${vm.openCount}' : ''}')],
                value: _ordering ? 'order' : 'mine',
                onChanged: (v) => setState(() => _ordering = v == 'order'),
              ),
              const SizedBox(height: 16),
              if (!s.isActive) ...[
                HCard(
                  color: c.accentSoft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HIcon('alert', size: 20, color: c.accentInk),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr('Product orders open once a HOLA sales officer verifies your salon. Customers can already find and book you.'),
                          style: T.sm(context).copyWith(color: c.accentInk),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ], 2),
            if (_ordering) ...[
              if (products.isEmpty)
                HCard(
                  child: EmptyState(icon: 'box', title: tr("HOLA hasn't published products yet"), text: tr('Products appear here as soon as HOLA adds them to the trade catalogue.')),
                )
              else
                ...staggered([for (final p in products) Padding(padding: const EdgeInsets.only(bottom: 12), child: ProductOrderCard(p))], 4),
              if (!cart.isEmpty) const SizedBox(height: 76), // room for the cart bar
            ] else if (orders.isEmpty)
              HCard(
                child: EmptyState(
                  icon: 'box',
                  title: tr('No orders yet'),
                  text: tr('Order colour, care and styling products from HOLA. Delivered to your salon.'),
                  cta: products.isEmpty || !s.isActive ? null : HButton(tr('Order products'), kind: BtnKind.secondary, small: true, onTap: () => setState(() => _ordering = true)),
                ),
              )
            else
              ...staggered([
                for (final o in orders)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OrderCard(
                      order: o,
                      onTap: () => pushPage(context, OrderDetailPage(id: o.id)),
                    ),
                  ),
              ], 4),
          ],
        ),
        // Cart: total and "Review order", floating above the tab bar.
        if (_ordering && !cart.isEmpty)
          Positioned(
            left: kGutter,
            right: kGutter,
            bottom: 100 + bottom,
            child: HCard(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
              radius: 18,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(rs(cart.total), style: T.h3(context)),
                        ),
                        Text(
                          '${plural(cart.lines.length, 'item')} · ${plural(cart.units, 'unit')}${cart.freeUnits > 0 ? ' · ${tr('{n} free', {'n': cart.freeUnits})}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.cap(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  HButton(
                    tr('Review order'),
                    icon: 'bag',
                    small: true,
                    onTap: s.isActive ? () => pushPage(context, ChangeNotifierProvider.value(value: cart, child: const OrderReviewPage())) : null,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Credit, filter and the order list (shared by the page and the tab).
List<Widget> _orders(BuildContext context, SalonOrdersViewModel vm, Salon s) {
  final c = context.c;
  final orders = vm.orders;
  return [
    ...staggered([
      Tap(
        onTap: () => pushPage(context, StatementPage(salonId: s.id)),
        child: CreditCard(salonId: s.id),
      ),
      const SizedBox(height: 6),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(
          onPressed: () => pushPage(context, StatementPage(salonId: s.id)),
          child: Text(tr('View statement'), style: T.link(context)),
        ),
      ),
      if (!s.isActive)
        HCard(
          color: c.accentSoft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HIcon('alert', size: 20, color: c.accentInk),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('Product orders open once a HOLA sales officer verifies your salon. Customers can already find and book you.'), style: T.sm(context).copyWith(color: c.accentInk)),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      Seg(
        opts: [('open', '${tr('Open')}${vm.openCount > 0 ? ' · ${vm.openCount}' : ''}'), ('delivered', tr('Delivered')), ('all', tr('All'))],
        value: vm.filter.name,
        onChanged: (v) => vm.setFilter(OrderFilter.values.byName(v)),
      ),
      const SizedBox(height: 16),
    ], 1),
    if (orders.isEmpty)
      EmptyState(
        icon: 'box',
        title: vm.all.isEmpty ? tr('No orders yet') : tr('Nothing here'),
        text: vm.all.isEmpty
            ? (s.isActive ? tr('Order colour, care and styling products from HOLA. Delivered to your salon.') : tr('Once HOLA verifies your salon you can order products here.'))
            : vm.filter == OrderFilter.open
            ? tr('No open orders right now.')
            : tr('No delivered orders right now.'),
        cta: vm.all.isEmpty && s.isActive
            ? HButton(
                tr('Browse products'),
                kind: BtnKind.secondary,
                small: true,
                onTap: () => pushPage(context, NewOrderPage(salonId: s.id)),
              )
            : null,
      )
    else
      ...staggered([
        for (final o in orders)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OrderCard(
              order: o,
              onTap: () => pushPage(context, OrderDetailPage(id: o.id)),
            ),
          ),
      ], 6),
  ];
}

/// Status filter helper for other features that list orders.
bool isOpenOrder(TradeOrder o) => OrderStatus.open.contains(o.status);
