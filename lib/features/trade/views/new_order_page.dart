import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/trade_view_models.dart';
import '../widgets/trade_widgets.dart';
import 'order_detail_page.dart';

/// HOLA trade catalogue → cart → review → place order. Used by salon owners
/// and by sales officers ordering on a salon's behalf.
class NewOrderPage extends StatelessWidget {
  const NewOrderPage({super.key, required this.salonId});
  final String salonId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => NewOrderViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), salonId),
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
    if (s == null) return HPage(title: tr('New order'), children: [EmptyState(icon: 'store', title: tr('Salon not found'), text: tr('It may have been removed.'))]);
    final all = vm.allProducts;
    final list = vm.products;
    return HPage(
      title: tr('New order'),
      footer: vm.isEmpty
          ? null
          : Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(rs(vm.total), style: T.h3(context))),
                  Text('${plural(vm.lines.length, 'item')} · ${plural(vm.units, 'unit')}${vm.freeUnits > 0 ? ' · ${tr('{n} free', {'n': vm.freeUnits})}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(context).copyWith(color: c.muted)),
                ]),
              ),
              const SizedBox(width: 12),
              HButton(tr('Review order'), icon: 'bag', onTap: () => pushPage(context, ChangeNotifierProvider.value(value: vm, child: const _Review()))),
            ]),
      children: [
        ...staggered([
          Text(tr('HOLA products'), style: T.h1(context)),
          Text(tr('Trade prices for {salon}', {'salon': s.name}), style: T.sub(context)),
          const SizedBox(height: 16),
          if (all.isNotEmpty) ...[
            HField(hint: tr('Search products or shades'), icon: 'search', onChanged: vm.setQuery),
            const SizedBox(height: 12),
            ChipRow(children: [
              HChip(tr('All'), on: vm.category == null, onTap: () => vm.setCategory(null)),
              for (final cat in vm.categories) HChip(tr(cat), on: vm.category == cat, onTap: () => vm.setCategory(cat)),
            ]),
            const SizedBox(height: 16),
          ],
        ]),
        if (all.isEmpty)
          EmptyState(icon: 'box', title: tr("HOLA hasn't published products yet"), text: tr('Products appear here as soon as HOLA adds them to the trade catalogue.'))
        else if (list.isEmpty)
          EmptyState(icon: 'search', title: tr('No products match'), text: tr('Try another search or category.'))
        else
          ...staggered([for (final p in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: _ProductCard(p))], 4),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard(this.p);
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProductThumb(p, size: 72),
        const SizedBox(width: 14),
        Expanded(
          child: VStack(gap: 8, [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: T.ttl(context)),
              Text(tr(p.category), style: T.sub(context)),
            ]),
            if (p.variants.length > 1)
              Wrap(spacing: 6, runSpacing: 6, children: [
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
              ])
            else
              Text(v.name, style: T.cap(context)),
            Text.rich(TextSpan(children: [TextSpan(text: rs(v.tradePrice), style: T.ttl(context)), TextSpan(text: '  ${tr('trade')}', style: T.cap(context))])),
            if (p.hasScheme) Align(alignment: Alignment.centerLeft, child: SchemeBadge(tr('Buy {buy} get {free}', {'buy': p.schemeBuy, 'free': p.schemeFree}))),
            Row(children: [
              Expanded(
                child: Text(
                  out ? tr('Out of stock') : v.stock < 10 ? tr('Only {n} left', {'n': v.stock}) : tr('{n} in stock', {'n': v.stock}),
                  style: T.cap(context).copyWith(color: out ? c.badInk : v.stock < 10 ? c.accentInk : c.muted, fontWeight: FontWeight.w600),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                child: q > 0
                    ? HStepper(key: const ValueKey('st'), value: q, max: max, onChanged: (n) => vm.setQty(p, v, n))
                    : HButton(tr('Add'), key: const ValueKey('add'), kind: BtnKind.secondary, small: true, sound: false, onTap: out || max == 0 ? null : () {
                        Sfx.add();
                        vm.setQty(p, v, 1);
                      }),
              ),
            ]),
            if (q > 0 && p.freeFor(q) > 0) Text(tr('+{n} free with this quantity', {'n': p.freeFor(q)}), style: T.cap(context).copyWith(color: c.ok, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
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
          style: T.cap(context).copyWith(
            fontWeight: FontWeight.w600,
            color: disabled ? c.subtle : on ? c.brandText : c.ink,
            decoration: disabled ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
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
    if (lines.isEmpty) {
      return HPage(title: tr('Review order'), children: [EmptyState(icon: 'bag', title: tr('Your cart is empty'), text: tr('Go back and add products to order.'))]);
    }
    return HPage(
      title: tr('Review order'),
      footer: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(rs(vm.total), style: T.h3(context))),
            Text(vm.payment == PaymentMethod.cod ? tr('Cash on delivery') : tr('On HOLA credit'), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(context).copyWith(color: c.muted)),
          ]),
        ),
        const SizedBox(width: 12),
        HButton(tr('Place order'), icon: 'check', onTap: () async {
          vm.notes = _notes.text;
          TradeOrder? placed;
          final ok = await attempt(() async => placed = await vm.place(), success: vm.overLimit ? tr('Order sent for credit review') : tr('Order placed'), confetti: !vm.overLimit);
          if (ok && context.mounted && placed != null) {
            // Back to where ordering started, then show the new order.
            final nav = Navigator.of(context);
            nav
              ..pop()
              ..pop();
            nav.push(HolaRoute(OrderDetailPage(id: placed!.id)));
          }
        }),
      ]),
      children: staggered([
        Text(tr('Review order'), style: T.h1(context)),
        Text(vm.salon?.name ?? '', style: T.sub(context)),
        const SizedBox(height: 16),
        // Reads like an invoice: billed salon, lines, then totals.
        HCard(
          child: VStack(gap: 12, [
            Row(children: [
              Expanded(child: Text(tr('ORDER SUMMARY'), style: T.eyebrow(context))),
              Text(plural(lines.length, 'item'), style: T.cap(context)),
            ]),
            const HDivider(),
            for (final l in lines)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.name, style: T.ttl(context)),
                    Text('${l.qty} × ${rs(l.unitPrice)}${l.freeQty > 0 ? ' · ${tr('+{n} free', {'n': l.freeQty})}' : ''}', style: T.sub(context)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(rs(l.total), style: T.ttl(context)),
              ]),
            const HDivider(),
            KV(tr('Units'), '${vm.units}${vm.freeUnits > 0 ? tr(' (incl. {n} free)', {'n': vm.freeUnits}) : ''}'),
            KV(tr('Payment'), vm.payment == PaymentMethod.cod ? tr('Cash on delivery') : tr('HOLA credit')),
            const HDivider(),
            Row(children: [
              Expanded(child: Text(tr('Total'), style: T.h3(context))),
              Text(rs(vm.total), style: T.h1(context).copyWith(fontSize: 26)),
            ]),
          ]),
        ),
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
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                HIcon('alert', size: 20, color: c.accentInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('This is {amount} over your available credit. It goes to HOLA for credit review before it ships.', {'amount': rs(vm.total - vm.credit.available)}), style: T.sm(context).copyWith(color: c.accentInk)),
                ),
              ]),
            ),
          ],
        ] else
          HCard(
            color: c.surface2,
            child: Row(children: [
              HIcon('cash', size: 22, color: c.ok),
              const SizedBox(width: 12),
              Expanded(child: Text(tr('Pay {amount} in cash to the rider when the order arrives.', {'amount': rs(vm.total)}), style: T.sm(context))),
            ]),
          ),
        const SizedBox(height: 24),
        HField(label: tr('Notes for HOLA (optional)'), hint: tr('e.g. Deliver after 2 pm'), controller: _notes, multiline: true),
        const SizedBox(height: 16),
      ]),
    );
  }
}
