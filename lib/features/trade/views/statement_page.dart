import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/trade_view_models.dart';
import '../widgets/trade_widgets.dart';

/// HOLA credit account: summary and ledger with running balance. Sales
/// officers can also record payments and change the credit terms.
class StatementPage extends StatelessWidget {
  const StatementPage({super.key, required this.salonId});
  final String salonId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => StatementViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), c.read<AuthRepository>(), salonId),
        child: const _Body(),
      );
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<StatementViewModel>();
    final c = context.c;
    final s = vm.salon;
    if (s == null) return HPage(title: tr('Credit statement'), children: [EmptyState(icon: 'store', title: tr('Salon not found'), text: tr('It may have been removed.'))]);
    final cr = vm.credit;
    final rows = vm.ledger;
    return HPage(
      title: tr('Credit statement'),
      footer: vm.isOfficer
          ? Row(children: [
              Expanded(child: HButton(tr('Credit terms'), icon: 'edit', kind: BtnKind.secondary, block: true, onTap: () => _terms(context, vm))),
              const SizedBox(width: 10),
              Expanded(child: HButton(tr('Record payment'), icon: 'cash', block: true, onTap: cr.outstanding <= 0 ? null : () => _payment(context, vm))),
            ])
          : null,
      children: [
        ...staggered([
          Text(tr('Credit statement'), style: T.h1(context)),
          Text(s.name, style: T.sub(context)),
          const SizedBox(height: 16),
          CreditCard(salonId: s.id),
          const SizedBox(height: 16),
          if (cr.limit > 0)
            HCard(
              child: VStack(gap: 10, [
                // Limit/outstanding/available are on the card above; these add the rest.
                KV(tr('Overdue'), cr.overdue > 0 ? rs(cr.overdue) : tr('Nothing overdue'), vColor: cr.overdue > 0 ? c.badInk : c.ok),
                KV(tr('Pay within'), plural(cr.days, 'day')),
                KV(tr('Last payment'), cr.lastPaymentAt == null ? tr('None yet') : '${rs(cr.lastPayment)} · ${dLabel(cr.lastPaymentAt!)}'),
              ]),
            ),
          const SizedBox(height: 24),
          SecHead(tr('Activity')),
          const SizedBox(height: 12),
        ]),
        if (rows.isEmpty)
          EmptyState(
            icon: 'doc',
            title: tr('No credit activity yet'),
            text: cr.limit > 0 ? tr('Orders paid on HOLA credit and payments show up here.') : tr('Credit orders and payments show up here once a credit line is set up.'),
          )
        else
          Reveal(
            i: 6,
            child: HCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                for (final (i, r) in rows.indexed) ...[
                  if (i > 0) const HDivider(),
                  _LedgerTile(r),
                ],
              ]),
            ),
          ),
        if (vm.isOfficer) const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _payment(BuildContext context, StatementViewModel vm) async {
    final amount = TextEditingController(), note = TextEditingController();
    final ok = await showHSheet<bool>(
      context,
      (ctx) => VStack(gap: 14, [
        SheetHead(tr('Record a payment'), sub: tr('{salon} owes {amount}.', {'salon': vm.salon?.name, 'amount': rs(vm.credit.outstanding)})),
        HField(label: tr('Amount received (Rs)'), hint: tr('e.g. 25000'), controller: amount, keyboard: TextInputType.number, icon: 'cash'),
        HField(label: tr('Note'), hint: tr('e.g. Bank transfer, cheque no.'), controller: note),
        HButton(tr('Record payment'), block: true, onTap: () async {
          final n = int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          if (await attempt(() => vm.recordPayment(n, note.text), success: tr('Payment recorded'), icon: 'cash') && ctx.mounted) Navigator.pop(ctx, true);
        }),
      ]),
    );
    if (ok != true) return;
  }

  Future<void> _terms(BuildContext context, StatementViewModel vm) async {
    final cr = vm.credit;
    final limit = TextEditingController(text: cr.limit == 0 ? '' : '${cr.limit}'), days = TextEditingController(text: '${cr.days}');
    await showHSheet<void>(
      context,
      (ctx) => VStack(gap: 14, [
        SheetHead(tr('Credit terms'), sub: tr('How much {salon} can order on credit, and how long they have to pay.', {'salon': vm.salon?.name})),
        HField(label: tr('Credit limit (Rs)'), hint: tr('0 = cash on delivery only'), controller: limit, keyboard: TextInputType.number, icon: 'cash'),
        HField(label: tr('Pay within (days)'), hint: '30', controller: days, keyboard: TextInputType.number, icon: 'cal'),
        HButton(tr('Save terms'), block: true, onTap: () async {
          int n(TextEditingController t) => int.tryParse(t.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          if (await attempt(() => vm.setTerms(n(limit), n(days)), success: tr('Credit terms saved')) && ctx.mounted) Navigator.pop(ctx);
        }),
      ]),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile(this.r);
  final LedgerRow r;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final e = r.entry;
    final charge = e.kind == 'CHARGE';
    final (icon, title, tint) = switch (e.kind) {
      'CHARGE' => ('box', tr('Order {code}', {'code': e.ref}), c.brandSoft),
      'PAYMENT' => ('cash', tr('Payment received'), c.okSoft),
      _ => ('x', tr('Cancelled {code}', {'code': e.ref}), c.bg2),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: tint, shape: BoxShape.circle), alignment: Alignment.center, child: HIcon(icon, size: 18, color: charge ? c.brandText : e.kind == 'PAYMENT' ? c.ok : c.muted)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
            Text([dLabel(e.at), if (e.note.isNotEmpty) e.note].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: T.cap(context)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${charge ? '+' : '−'}${rs(e.amount)}', style: T.ttl(context).copyWith(color: charge ? c.ink : c.ok)),
          Text(tr('Bal {amount}', {'amount': rs(r.balance)}), style: T.cap(context)),
        ]),
      ]),
    );
  }
}
