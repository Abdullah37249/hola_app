import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/trade_view_models.dart';
import '../widgets/trade_widgets.dart';
import 'product_editor_page.dart';

/// HOLA trade catalogue management for sales officers: products, stock, schemes.
class ProductsAdminPage extends StatelessWidget {
  const ProductsAdminPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => ProductsAdminViewModel(c.read<TradeRepository>()),
        child: const _Body(),
      );
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductsAdminViewModel>();
    final c = context.c;
    final all = vm.all;
    final list = vm.products;
    return HPage(
      title: tr('Products'),
      footer: HButton(tr('Add product'), icon: 'plus', block: true, onTap: () => pushPage(context, const ProductEditorPage())),
      children: [
        ...staggered([
          Text(tr('Products'), style: T.h1(context)),
          Text(tr('The HOLA trade catalogue salons order from'), style: T.sub(context)),
          const SizedBox(height: 16),
          if (all.isNotEmpty) ...[
            Row(children: [
              Expanded(child: Kpi(tr('Products'), all.where((p) => p.active).length)),
              const SizedBox(width: 10),
              Expanded(child: Kpi(tr('Sizes & shades'), all.fold(0, (s, p) => s + p.variants.length))),
              const SizedBox(width: 10),
              Expanded(child: Kpi(tr('Low stock'), vm.lowCount)),
            ]),
            const SizedBox(height: 16),
            ChipRow(children: [
              HChip(tr('All'), on: vm.category == null, onTap: () => vm.setCategory(null)),
              for (final cat in productCategories)
                if (all.any((p) => p.category == cat)) HChip(tr(cat), on: vm.category == cat, onTap: () => vm.setCategory(cat)),
            ]),
            const SizedBox(height: 16),
          ],
        ]),
        if (all.isEmpty)
          EmptyState(
            icon: 'box',
            title: tr('No products yet'),
            text: tr('Add HOLA products with their sizes or shades, trade prices and stock. Salons can order them straight away.'),
            cta: HButton(tr('Add the first product'), kind: BtnKind.secondary, small: true, onTap: () => pushPage(context, const ProductEditorPage())),
          )
        else
          ...staggered([
            for (final p in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: HCard(
                  onTap: () => pushPage(context, ProductEditorPage(productId: p.id)),
                  child: VStack(gap: 10, [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ProductThumb(p, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, style: T.ttl(context)),
                          Text(tr('{category} · from {price}', {'category': tr(p.category), 'price': rs(p.fromPrice)}), style: T.sub(context)),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            if (!p.active) ToneBadge(tr('Hidden'), tone: 'mute'),
                            if (p.hasScheme) SchemeBadge(tr('Buy {buy} get {free}', {'buy': p.schemeBuy, 'free': p.schemeFree})),
                          ]),
                        ]),
                      ),
                      HIcon('chev', size: 18, color: c.subtle),
                    ]),
                    const HDivider(),
                    for (final v in p.variants)
                      Row(children: [
                        Expanded(child: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(context))),
                        Text(
                          v.stock <= 0 ? tr('Out of stock') : tr('{n} in stock', {'n': v.stock}),
                          style: T.cap(context).copyWith(fontWeight: FontWeight.w600, color: v.stock < ProductsAdminViewModel.lowStock ? (v.stock <= 0 ? c.badInk : c.accentInk) : c.muted),
                        ),
                        const SizedBox(width: 8),
                        HButton(tr('Restock'), kind: BtnKind.soft, small: true, onTap: () => _restock(context, vm, p, v)),
                      ]),
                  ]),
                ),
              ),
          ], 5),
        if (all.isNotEmpty && list.isEmpty) EmptyState(icon: 'search', title: tr('Nothing in this category'), text: tr('Pick another category.')),
      ],
    );
  }

  Future<void> _restock(BuildContext context, ProductsAdminViewModel vm, Product p, Variant v) async {
    final qty = await askText(context, title: tr('Restock {name}', {'name': p.name}), body: tr('{variant} · {n} in stock now', {'variant': v.name, 'n': v.stock}), label: tr('Units received'), hint: tr('e.g. 48'), confirm: tr('Add to stock'), minLength: 1, multiline: false);
    if (qty == null) return;
    final n = int.tryParse(qty.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    await attempt(() => vm.restock(p, v, n), success: tr('Stock updated'), icon: 'box');
  }
}
