import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/trade_view_models.dart';
import '../widgets/promo_card.dart';
import '../widgets/trade_widgets.dart';
import 'order_detail_page.dart';

/// HOLA trade catalogue → cart → review → place order. Used by salon owners
/// and by sales officers ordering on a salon's behalf.
class NewOrderPage extends StatelessWidget {
  const NewOrderPage({super.key, required this.salonId, this.coupon});
  final String salonId;

  /// A HOLA offer's code to apply when the order is reviewed.
  final String? coupon;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => NewOrderViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), salonId, suggestedCoupon: coupon),
    child: const _Catalogue(),
  );
}

class _Catalogue extends StatelessWidget {
  const _Catalogue();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NewOrderViewModel>();
    final c = context.c;
    final s = vm.salon;
    if (s == null) {
      return HPage(
        title: tr('New order'),
        children: [EmptyState(icon: 'store', title: tr('Salon not found'), text: tr('It may have been removed.'))],
      );
    }
    final all = vm.allProducts;
    final list = vm.products;
    return HPage(
      title: tr('New order'),
      footer: vm.isEmpty
          ? null
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(rs(vm.total), style: T.h3(context)),
                      ),
                      Text(
                        '${plural(vm.lines.length, 'item')} · ${plural(vm.units, 'unit')}${vm.freeUnits > 0 ? ' · ${tr('{n} free', {'n': vm.freeUnits})}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.sm(context).copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                HButton(
                  tr('Review order'),
                  icon: 'bag',
                  onTap: () => pushPage(context, ChangeNotifierProvider.value(value: vm, child: const OrderReviewPage())),
                ),
              ],
            ),
      children: [
        ...staggered([
          Text(tr('HOLA products'), style: T.h1(context)),
          Text(tr('Trade prices for {salon}', {'salon': s.name}), style: T.sub(context)),
          const SizedBox(height: 16),
          if (all.isNotEmpty) ...[
            HField(hint: tr('Search products or shades'), icon: 'search', onChanged: vm.setQuery),
            const SizedBox(height: 12),
            ChipRow(
              children: [
                HChip(tr('All'), on: vm.category == null, onTap: () => vm.setCategory(null)),
                for (final cat in vm.categories) HChip(tr(cat), on: vm.category == cat, onTap: () => vm.setCategory(cat)),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ]),
        if (all.isEmpty)
          EmptyState(icon: 'box', title: tr("HOLA hasn't published products yet"), text: tr('Products appear here as soon as HOLA adds them to the trade catalogue.'))
        else if (list.isEmpty)
          EmptyState(icon: 'search', title: tr('No products match'), text: tr('Try another search or category.'))
        else
          ...staggered([for (final p in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: ProductOrderCard(p))], 4),
      ],
    );
  }
}

class ProductOrderCard extends StatelessWidget {
  const ProductOrderCard(this.p, {super.key});
  final Product p;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NewOrderViewModel>();
    final c = context.c;
    final v = vm.variantFor(p);
    final q = vm.qty(p, v);
    final max = vm.maxQty(p, v);
    final out = v.stock <= 0;
    return HCard(
      // Tap the card for the full product: photo, description, sizes, prices.
      onTap: () => showProductDetail(context, p),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductThumb(p, size: 72),
          const SizedBox(width: 14),
          Expanded(
            child: VStack(gap: 8, [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: T.ttl(context)),
                  // Size (one variant) and type on one line, as on HOLA's cards.
                  Text(p.variants.length > 1 ? tr(p.category) : '${v.name} · ${tr(p.category)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sub(context)),
                ],
              ),
              if (p.variants.length > 1) _variants(p, v, vm),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: rs(v.tradePrice), style: T.ttl(context)),
                    TextSpan(text: '  ${tr('trade')}', style: T.cap(context)),
                  ],
                ),
              ),
              if (p.hasScheme) Align(alignment: Alignment.centerLeft, child: SchemeBadge(tr('Buy {buy} get {free}', {'buy': p.schemeBuy, 'free': p.schemeFree}))),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      out
                          ? tr('Out of stock')
                          : v.stock < 10
                          ? tr('Only {n} left', {'n': v.stock})
                          : tr('{n} in stock', {'n': v.stock}),
                      style: T
                          .cap(context)
                          .copyWith(
                            color: out
                                ? c.badInk
                                : v.stock < 10
                                ? c.accentInk
                                : c.muted,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                    child: q > 0
                        ? HStepper(key: const ValueKey('st'), value: q, max: max, onChanged: (n) => vm.setQty(p, v, n))
                        : HButton(
                            tr('Add'),
                            key: const ValueKey('add'),
                            kind: BtnKind.secondary,
                            small: true,
                            sound: false,
                            onTap: out || max == 0
                                ? null
                                : () {
                                    Sfx.add();
                                    vm.setQty(p, v, 1);
                                  },
                          ),
                  ),
                ],
              ),
              if (q > 0 && p.freeFor(q) > 0)
                Text(
                  tr('+{n} free with this quantity', {'n': p.freeFor(q)}),
                  style: T.cap(context).copyWith(color: c.ok, fontWeight: FontWeight.w600),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Pop-up with everything about a product, and adding it to the order.
Future<void> showProductDetail(BuildContext context, Product p) {
  final vm = context.read<NewOrderViewModel>();
  return showHSheet(context, (_) => ChangeNotifierProvider.value(value: vm, child: _ProductDetail(p)));
}

class _ProductDetail extends StatelessWidget {
  const _ProductDetail(this.p);
  final Product p;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NewOrderViewModel>();
    final c = context.c;
    final v = vm.variantFor(p);
    final q = vm.qty(p, v);
    final max = vm.maxQty(p, v);
    final out = v.stock <= 0;
    final margin = v.retailPrice - v.tradePrice;
    return VStack(gap: 16, [
      // Big photo on white, like HOLA's shop.
      Container(
        height: 230,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.line),
        ),
        alignment: Alignment.center,
        child: p.imageUrl.startsWith('https://')
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Image.network(
                  p.imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Bottle(color: p.color, shape: p.shape, height: 180, scale: 1.4),
                ),
              )
            : Bottle(color: p.color, shape: p.shape, height: 180, scale: 1.4),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: T.h2(context)),
          const SizedBox(height: 2),
          Text(p.variants.length > 1 ? tr(p.category) : '${v.name} · ${tr(p.category)}', style: T.sub(context)),
        ],
      ),
      // Price: trade, retail, and what the salon makes reselling it.
      HCard(
        color: c.surface2,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Trade price'), style: T.cap(context)),
                  Text(rs(v.tradePrice), style: T.h2(context)),
                ],
              ),
            ),
            if (v.retailPrice > 0)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Retail price'), style: T.cap(context)),
                    Text(rs(v.retailPrice), style: T.h3(context).copyWith(color: c.muted)),
                    if (margin > 0)
                      Text(
                        tr('You earn {amount} each', {'amount': rs(margin)}),
                        style: T.cap(context).copyWith(color: c.ok, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (p.hasScheme)
        Row(
          children: [
            SchemeBadge(tr('Buy {buy} get {free}', {'buy': p.schemeBuy, 'free': p.schemeFree})),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('Every {buy} you order, {free} more come free.', {'buy': p.schemeBuy, 'free': p.schemeFree}), style: T.cap(context))),
          ],
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('About this product'), style: T.ttl(context)),
          const SizedBox(height: 4),
          Text(
            p.description.trim().isEmpty ? tr("HOLA hasn't added a description for this product yet.") : p.description.trim(),
            style: T.body(context).copyWith(color: p.description.trim().isEmpty ? c.muted : null),
          ),
        ],
      ),
      if (p.variants.length > 1)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Sizes and shades · {n}', {'n': p.variants.length}), style: T.ttl(context)),
            const SizedBox(height: 8),
            _variants(p, v, vm),
          ],
        ),
      Text(
        out
            ? tr('Out of stock')
            : v.stock < 10
            ? tr('Only {n} left', {'n': v.stock})
            : tr('{n} in stock', {'n': v.stock}),
        style: T
            .sm(context)
            .copyWith(
              color: out
                  ? c.badInk
                  : v.stock < 10
                  ? c.accentInk
                  : c.muted,
              fontWeight: FontWeight.w600,
            ),
      ),
      // Add to the order right here.
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q > 0 ? rs(v.tradePrice * q) : tr('Not in your order'), style: T.h3(context)),
                if (q > 0 && p.freeFor(q) > 0)
                  Text(
                    tr('+{n} free with this quantity', {'n': p.freeFor(q)}),
                    style: T.cap(context).copyWith(color: c.ok, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          q > 0
              ? HStepper(value: q, max: max, onChanged: (n) => vm.setQty(p, v, n))
              : HButton(
                  tr('Add to order'),
                  icon: 'plus',
                  small: true,
                  onTap: out || max == 0
                      ? null
                      : () {
                          Sfx.add();
                          vm.setQty(p, v, 1);
                        },
                ),
        ],
      ),
      HButton(tr('Done'), kind: BtnKind.secondary, block: true, onTap: () => Navigator.of(context).pop()),
    ]);
  }
}

/// Sizes or shades. A few wrap; many (e.g. 99 colour shades) scroll in one row.
Widget _variants(Product p, Variant v, NewOrderViewModel vm) {
  final chips = [
    for (final x in p.variants)
      _VariantChip(
        label: x.name,
        on: x.id == v.id,
        disabled: x.stock <= 0,
        count: vm.qty(p, x),
        onTap: () {
          Sfx.tap();
          vm.pickVariant(p, x);
        },
      ),
  ];
  if (chips.length <= 6) return Wrap(spacing: 6, runSpacing: 6, children: chips);
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [for (final ch in chips) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: ch)],
    ),
  );
}

/// One cart line in the review: photo, name, price, quantity and remove.
class _ReviewLine extends StatelessWidget {
  const _ReviewLine(this.l, {super.key});
  final OrderLine l;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<NewOrderViewModel>();
    final c = context.c;
    final p = vm.productOf(l);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p != null) ...[ProductThumb(p, size: 44), const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
              Text('${rs(l.unitPrice)} ${tr('each')}${l.freeQty > 0 ? ' · ${tr('+{n} free', {'n': l.freeQty})}' : ''}', style: T.sub(context)),
              const SizedBox(height: 8),
              Row(
                children: [
                  HStepper(value: l.qty, max: vm.maxFor(l), onChanged: (n) => vm.setLineQty(l, n)),
                  const Spacer(),
                  Text(rs(l.total), style: T.ttl(context)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        // Remove the product from the order.
        IconButton(
          tooltip: tr('Remove'),
          visualDensity: VisualDensity.compact,
          onPressed: () {
            Sfx.tap();
            vm.setLineQty(l, 0);
          },
          icon: HIcon('x', size: 18, color: c.badInk),
        ),
      ],
    );
  }
}

class _VariantChip extends StatelessWidget {
  const _VariantChip({required this.label, required this.on, required this.disabled, required this.count, required this.onTap});
  final String label;
  final bool on, disabled;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? c.brandSoft : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? c.brand : c.line, width: on ? 1.5 : 1),
        ),
        child: Text(
          count > 0 ? '$label · $count' : label,
          style: T
              .cap(context)
              .copyWith(
                fontWeight: FontWeight.w600,
                color: disabled
                    ? c.subtle
                    : on
                    ? c.brandText
                    : c.ink,
                decoration: disabled ? TextDecoration.lineThrough : null,
              ),
        ),
      ),
    );
  }
}

class OrderReviewPage extends StatefulWidget {
  const OrderReviewPage({super.key});
  @override
  State<OrderReviewPage> createState() => _OrderReviewPageState();
}

class _OrderReviewPageState extends State<OrderReviewPage> {
  late final _notes = TextEditingController(text: context.read<NewOrderViewModel>().notes);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NewOrderViewModel>();
    final c = context.c;
    final lines = vm.lines;
    // The offer the salon came from: apply it once the cart has items.
    if (vm.suggestedCoupon case final code? when lines.isNotEmpty && vm.coupon == null && !vm.couponBusy) {
      vm.suggestedCoupon = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => vm.applyCoupon(code));
    }
    if (lines.isEmpty) {
      return HPage(
        title: tr('Review order'),
        children: [EmptyState(icon: 'bag', title: tr('Your cart is empty'), text: tr('Go back and add products to order.'))],
      );
    }
    return HPage(
      title: tr('Review order'),
      footer: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(rs(vm.total), style: T.h3(context)),
                ),
                Text(
                  vm.payment == PaymentMethod.cod ? tr('Cash on delivery') : tr('On HOLA credit'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.sm(context).copyWith(color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          HButton(
            tr('Place order'),
            icon: 'check',
            onTap: () async {
              vm.notes = _notes.text;
              TradeOrder? placed;
              final ok = await attempt(() async => placed = await vm.place(), success: vm.overLimit ? tr('Order sent for credit review') : tr('Order placed'), confetti: !vm.overLimit);
              if (ok && context.mounted && placed != null) {
                // Back to where ordering started, then show the new order.
                final nav = Navigator.of(context);
                // Back to the main screen, then show the new order.
                nav.popUntil((r) => r.isFirst);
                nav.push(HolaRoute(OrderDetailPage(id: placed!.id)));
              }
            },
          ),
        ],
      ),
      children: staggered([
        Text(tr('Review order'), style: T.h1(context)),
        Text(vm.salon?.name ?? '', style: T.sub(context)),
        const SizedBox(height: 16),
        // Reads like an invoice: billed salon, lines, then totals.
        HCard(
          child: VStack(gap: 12, [
            Row(
              children: [
                Expanded(child: Text(tr('ORDER SUMMARY'), style: T.eyebrow(context))),
                Text(plural(lines.length, 'item'), style: T.cap(context)),
              ],
            ),
            const HDivider(),
            for (final l in lines) _ReviewLine(l, key: ValueKey('${l.productId}/${l.variantId}')),
            const HDivider(),
            KV(tr('Units'), '${vm.units}${vm.freeUnits > 0 ? tr(' (incl. {n} free)', {'n': vm.freeUnits}) : ''}'),
            KV(tr('Payment'), vm.payment == PaymentMethod.cod ? tr('Cash on delivery') : tr('HOLA credit')),
            if (vm.coupon case final cp?) ...[
              KV(tr('Subtotal'), rs(vm.subtotal)),
              KV(tr('Coupon {code}', {'code': cp.couponCode}), '− ${rs(cp.discount)}', vColor: c.ok),
            ],
            const HDivider(),
            Row(
              children: [
                Expanded(child: Text(tr('Total'), style: T.h3(context))),
                Text(rs(vm.total), style: T.h1(context).copyWith(fontSize: 26)),
              ],
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const _CouponBox(),
        // "You have N available coupons": HOLA's offers for this salon.
        if (vm.coupon == null && vm.availableCoupons.isNotEmpty) ...[
          const SizedBox(height: 10),
          Tap(
            onTap: () => _pickCoupon(context, vm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  HIcon('sparkle', size: 18, color: c.accentInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      vm.availableCoupons.length == 1 ? tr('You have 1 available coupon') : tr('You have {n} available coupons', {'n': vm.availableCoupons.length}),
                      style: T.sm(context).copyWith(color: c.accentInk, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    tr('View'),
                    style: T.sm(context).copyWith(color: c.accentInk, fontWeight: FontWeight.w700),
                  ),
                  HIcon('chev', size: 16, color: c.accentInk),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SecHead(tr('Payment')),
        const SizedBox(height: 12),
        if (vm.hasCredit) ...[
          Seg(opts: [('credit', tr('HOLA credit')), ('cod', tr('Cash on delivery'))], value: vm.payment.name, onChanged: (v) => vm.setPayment(PaymentMethod.values.byName(v))),
          const SizedBox(height: 12),
        ],
        if (vm.payment == PaymentMethod.credit) ...[
          CreditCard(salonId: vm.salonId),
          if (vm.overLimit) ...[
            const SizedBox(height: 12),
            HCard(
              color: c.accentSoft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HIcon('alert', size: 20, color: c.accentInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('This is {amount} over your available credit. It goes to HOLA for credit review before it ships.', {'amount': rs(vm.total - vm.credit.available)}),
                      style: T.sm(context).copyWith(color: c.accentInk),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ] else
          HCard(
            color: c.surface2,
            child: Row(
              children: [
                HIcon('cash', size: 22, color: c.ok),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('Pay {amount} in cash to the rider when the order arrives.', {'amount': rs(vm.total)}), style: T.sm(context))),
              ],
            ),
          ),
        const SizedBox(height: 24),
        HField(label: tr('Notes for HOLA (optional)'), hint: tr('e.g. Deliver after 2 pm'), controller: _notes, multiline: true),
        const SizedBox(height: 16),
      ]),
    );
  }
}

/// "Have a coupon?": HOLA checks the code against this cart and the total
/// drops by its discount; a bad code shows HOLA's reason under the field.
class _CouponBox extends StatefulWidget {
  const _CouponBox();
  @override
  State<_CouponBox> createState() => _CouponBoxState();
}

class _CouponBoxState extends State<_CouponBox> {
  final code = TextEditingController();

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NewOrderViewModel>();
    final c = context.c;
    final cp = vm.coupon;
    if (cp != null) {
      return HCard(
        color: c.okSoft,
        child: Row(
          children: [
            HIcon('check', size: 20, color: c.ok),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('{code} applied · you save {amount}', {'code': cp.couponCode, 'amount': rs(cp.discount)}), style: T.ttl(context).copyWith(color: c.ok)),
                  if ((cp.offer ?? cp.campaign ?? '').isNotEmpty) Text(cp.offer?.isNotEmpty == true ? cp.offer! : cp.campaign!, style: T.cap(context)),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                Sfx.tap();
                code.clear();
                vm.removeCoupon();
              },
              child: Text(
                tr('Remove'),
                style: T.sm(context).copyWith(color: c.badInk, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    void apply() {
      FocusScope.of(context).unfocus();
      vm.applyCoupon(code.text);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: HField(
                label: tr('Have a coupon?'),
                hint: tr('e.g. HOLA-EID25'),
                controller: code,
                icon: 'sparkle',
                action: TextInputAction.done,
                onSubmitted: (_) => apply(),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            HButton(vm.couponBusy ? tr('Checking…') : tr('Apply'), kind: BtnKind.secondary, onTap: vm.couponBusy || code.text.trim().isEmpty ? null : apply),
          ],
        ),
        if (vm.couponError case final e?) ...[const SizedBox(height: 6), Text(e, style: T.sm(context).copyWith(color: c.badInk))],
      ],
    );
  }
}

/// HOLA's offers for this salon; tapping one applies its code to the order.
Future<void> _pickCoupon(BuildContext context, NewOrderViewModel vm) => showHSheet(
  context,
  (ctx) => VStack(gap: 12, [
    SheetHead(tr('Your coupons'), sub: tr('Offers HOLA sent your salon. Pick one to use on this order.')),
    for (final cp in vm.availableCoupons)
      PromoCard(
        cp,
        onUse: () {
          Navigator.pop(ctx);
          vm.applyCoupon(cp.code);
        },
      ),
  ]),
);
