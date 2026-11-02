import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../../chat/chat.dart';
import '../viewmodels/bookings_view_models.dart';

/// HOLA Professional products customers see used in their salons.
class CustomerShop extends StatelessWidget {
  const CustomerShop({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => ShopViewModel(c.read<SalonRepository>(), c.read<AuthRepository>(), c.read<BookingRepository>(), c.read<TradeRepository>()),
        child: const _ShopBody(),
      );
}

class _ShopBody extends StatelessWidget {
  const _ShopBody();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ShopViewModel>();
    final c = context.c;
    final list = vm.items;
    final cats = vm.categories;
    return BandView(role: 'customer', bandHeight: 250, children: [
      ...staggered([
        TopHead(title: tr('Products'), sub: tr('The HOLA Professional range salons use')),
        const SizedBox(height: 14),
        if (cats.length > 1) ...[
          ChipRow(children: [
            HChip(tr('All'), on: vm.category == null, onTap: () => vm.setCategory(null)),
            for (final x in cats) HChip(tr(x), on: vm.category == x, onTap: () => vm.setCategory(x)),
          ]),
          const SizedBox(height: 18),
        ] else
          const SizedBox(height: 24),
      ]),
      if (list.isEmpty)
        Reveal(i: 3, child: HCard(child: EmptyState(icon: 'bag', title: tr('No products yet'), text: tr('HOLA Professional products will appear here once they are added to the catalogue.'))))
      else
        GridView.builder(
          padding: EdgeInsets.zero,
          key: ValueKey(vm.category),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisSpacing: 16, crossAxisSpacing: 12, mainAxisExtent: 174 + MediaQuery.textScalerOf(context).scale(62)),
          itemBuilder: (_, i) => Reveal(i: i + 3, child: _ProductCard(list[i])),
        ),
      if (list.isNotEmpty) ...[
        const SizedBox(height: 20),
        Reveal(
          i: 10,
          child: HCard(
            color: c.surface2,
            child: Row(children: [
              HIcon('store', size: 24, color: c.brandText),
              const SizedBox(width: 12),
              Expanded(child: Text(tr('Prices are recommended retail. Ask your salon about availability.'), style: T.sm(context))),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _ProductCard extends StatelessWidget {
  final Product p;
  const _ProductCard(this.p);
  @override
  Widget build(BuildContext context) {
    final vm = context.read<ShopViewModel>();
    return Tap(
      onTap: () => showProductSheet(context, p, vm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(color: context.c.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: context.c.line)),
            clipBehavior: Clip.antiAlias,
            child: Bottle(color: p.color, shape: p.shape),
          ),
        ),
        const SizedBox(height: 10),
        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
        Text(tr(p.category), maxLines: 1, style: T.sm(context).copyWith(color: context.c.muted)),
        Text(tr('from {price}', {'price': rs(vm.retailFrom(p))}), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(context).copyWith(color: context.c.ink, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

void showProductSheet(BuildContext context, Product p, ShopViewModel vm) {
  final salons = vm.bookedSalons;
  showHSheet(context, (ctx) {
    final c = ctx.c;
    final sizes = p.variants.where((v) => v.retailPrice > 0).toList();
    return VStack(gap: 16, [
      Bottle(color: p.color, shape: p.shape, height: 200, scale: 1.3),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(p.category).toUpperCase(), style: T.eyebrow(ctx)),
        Text(p.name, style: T.h2(ctx)),
      ]),
      if (p.description.isNotEmpty) Text(p.description, style: T.body(ctx)),
      Group(children: [
        for (final v in sizes)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [Expanded(child: Text(v.name, style: T.sm(ctx).copyWith(color: c.ink))), Text(rs(v.retailPrice), style: T.ttl(ctx))]),
          ),
      ]),
      if (salons.isNotEmpty)
        HButton(tr('Ask {salon} about it', {'salon': salons.first.name}), icon: 'msg', block: true, onTap: () {
          Navigator.pop(ctx);
          openSalonChat(context, salons.first.id);
        })
      else
        Text(tr('Book a salon on HOLA to ask them about this product.'), style: T.cap(ctx), textAlign: TextAlign.center),
    ]);
  });
}
