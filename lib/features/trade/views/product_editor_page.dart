import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/trade_view_models.dart';
import '../widgets/trade_widgets.dart';

/// Add or edit a HOLA product: details, look, sizes/shades with prices and
/// stock, and an optional "buy N get M" scheme.
class ProductEditorPage extends StatelessWidget {
  const ProductEditorPage({super.key, this.productId});
  final String? productId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => ProductEditorViewModel(c.read<TradeRepository>(), productId), child: const _Body());
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductEditorViewModel>();
    final c = context.c;
    final preview = Product(id: '', name: vm.name, category: vm.category, color: vm.color, shape: vm.shape, variants: const [], createdAt: DateTime(0));
    return HPage(
      title: vm.isNew ? tr('Add product') : tr('Edit product'),
      footer: HButton(
        vm.isNew ? tr('Add product') : tr('Save changes'),
        icon: 'check',
        block: true,
        onTap: () async {
          if (await attempt(vm.save, success: vm.isNew ? tr('Product added') : tr('Product saved')) && context.mounted) Navigator.pop(context);
        },
      ),
      children: staggered([
        Row(
          children: [
            ProductThumb(preview, size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vm.name.trim().isEmpty ? (vm.isNew ? tr('New product') : tr('Product')) : vm.name.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: T.h2(context)),
                  Text(tr(vm.category), style: T.sub(context)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        VStack(gap: 14, [
          HField(label: tr('Product name'), hint: tr('e.g. Bond Repair Shampoo'), initial: vm.name, onChanged: (v) => vm.set(() => vm.name = v)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Label(tr('Category')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final cat in productCategories) HChip(tr(cat), on: vm.category == cat, onTap: () => vm.set(() => vm.category = cat))],
              ),
            ],
          ),
          HField(label: tr('Description (optional)'), hint: tr('What it does and who it is for'), initial: vm.description, multiline: true, onChanged: (v) => vm.description = v),
        ]),
        const SizedBox(height: 24),
        SecHead(tr('Look in the catalogue')),
        const SizedBox(height: 12),
        HCard(
          child: VStack(gap: 14, [
            Text(tr('Colour and shape of the bottle salons see.'), style: T.cap(context)),
            VStack(gap: 14, [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final col in ProductEditorViewModel.colors)
                    GestureDetector(
                      onTap: () {
                        Sfx.tap();
                        vm.set(() => vm.color = col);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(col),
                          shape: BoxShape.circle,
                          border: Border.all(color: vm.color == col ? c.brand : c.line, width: vm.color == col ? 3 : 1),
                          boxShadow: c.lift,
                        ),
                      ),
                    ),
                ],
              ),
              Seg(opts: [for (final s in ProductEditorViewModel.shapes) (s.$1, tr(s.$2))], value: vm.shape, onChanged: (v) => vm.set(() => vm.shape = v)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
        SecHead(tr('Sizes & shades'), action: tr('Add'), onAction: vm.addVariant),
        const SizedBox(height: 12),
        for (final (i, v) in vm.variants.indexed)
          Padding(
            key: ValueKey(v.id),
            padding: const EdgeInsets.only(bottom: 12),
            child: HCard(
              child: VStack(gap: 12, [
                Row(
                  children: [
                    Expanded(child: Text(tr('Option {n}', {'n': i + 1}), style: T.ttl(context))),
                    if (vm.variants.length > 1)
                      TextButton(
                        onPressed: () => vm.removeVariant(v),
                        child: Text(tr('Remove'), style: T.link(context).copyWith(color: c.badInk)),
                      ),
                  ],
                ),
                HField(label: tr('Size or shade'), hint: tr('e.g. 1 L or 7.1 Ash Blonde'), initial: v.name, onChanged: (x) => v.name = x),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: HField(label: tr('Trade price'), hint: 'Rs', initial: v.trade, keyboard: TextInputType.number, onChanged: (x) => v.trade = x),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: HField(label: tr('Retail price'), hint: tr('Optional'), initial: v.retail, keyboard: TextInputType.number, onChanged: (x) => v.retail = x),
                    ),
                  ],
                ),
                HField(label: tr('Units in stock'), hint: '0', initial: v.stock, keyboard: TextInputType.number, onChanged: (x) => v.stock = x),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        SecHead(tr('Scheme')),
        const SizedBox(height: 12),
        HCard(
          child: VStack(gap: 14, [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Free units offer'), style: T.ttl(context)),
                      Text(tr('e.g. buy 6, get 1 free'), style: T.cap(context)),
                    ],
                  ),
                ),
                HSwitch(on: vm.hasScheme, onChanged: vm.toggleScheme),
              ],
            ),
            if (vm.hasScheme) ...[
              Row(
                children: [
                  Expanded(child: Text(tr('Buy'), style: T.sm(context))),
                  HStepper(value: vm.schemeBuy, min: 1, max: 99, onChanged: (n) => vm.set(() => vm.schemeBuy = n)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Text(tr('Get free'), style: T.sm(context))),
                  HStepper(value: vm.schemeFree, min: 1, max: 99, onChanged: (n) => vm.set(() => vm.schemeFree = n)),
                ],
              ),
              Align(alignment: Alignment.centerLeft, child: SchemeBadge(tr('Buy {buy} get {free}', {'buy': vm.schemeBuy, 'free': vm.schemeFree}))),
            ],
          ]),
        ),
        const SizedBox(height: 24),
        HCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Show to salons'), style: T.ttl(context)),
                    Text(vm.active ? tr('Salons can order this product') : tr('Hidden from the catalogue'), style: T.cap(context)),
                  ],
                ),
              ),
              HSwitch(on: vm.active, onChanged: (v) => vm.set(() => vm.active = v)),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(fontFamily: T.f, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w600, color: context.c.ink),
    ),
  );
}
