import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/option_tile.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/trade_view_models.dart';

/// The salon pays its HOLA credit balance: to the rider, or to HOLA directly
/// in cash or online (with a receipt). Finance confirms before it counts.
class PayOutstandingPage extends StatelessWidget {
  const PayOutstandingPage({super.key, required this.salonId});
  final String salonId;
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => PayOutstandingViewModel(c.read<TradeRepository>(), salonId), child: const _Body());
}

class _Body extends StatefulWidget {
  const _Body();
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final amount = TextEditingController(), reference = TextEditingController();
  bool _filled = false;

  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    super.dispose();
  }

  int get _amount => int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PayOutstandingViewModel>();
    final cr = vm.credit;
    // Start with the full amount once the balance is known.
    if (!_filled && vm.payable > 0) {
      _filled = true;
      amount.text = '${vm.payable}';
    }
    final ready = _amount > 0 && (vm.method != PayMethod.online || (vm.proofPath != null && reference.text.trim().isNotEmpty));
    return HPage(
      title: tr('Pay outstanding'),
      alwaysTitle: true,
      footer: vm.payable <= 0 ? null : HButton(_cta(vm.method), icon: 'check', block: true, onTap: ready ? () => _send(context, vm) : null),
      children: staggered([
        const SizedBox(height: 8),
        // What the salon owes, big and clear.
        HCard(
          gradient: G.credit,
          child: VStack(gap: 6, [
            Text(tr('You owe HOLA'), style: T.sm(context).copyWith(color: Colors.white.withValues(alpha: .8))),
            Text(rs(cr.outstanding), style: T.h1(context).copyWith(color: Colors.white)),
            if (cr.overdue > 0)
              ToneBadge(tr('{amount} overdue', {'amount': rs(cr.overdue)}), tone: 'bad')
            else
              Text(tr('Pay within {days} of each order', {'days': plural(cr.days, 'day')}), style: T.cap(context).copyWith(color: Colors.white.withValues(alpha: .75))),
            if (vm.waiting > 0) Text(tr('{amount} already sent, waiting for HOLA to confirm', {'amount': rs(vm.waiting)}), style: T.cap(context).copyWith(color: Colors.white)),
          ]),
        ),
        const SizedBox(height: 20),
        if (vm.payable <= 0)
          HCard(
            child: EmptyState(
              icon: 'check',
              title: cr.outstanding <= 0 ? tr('Nothing to pay') : tr('All of it is on its way'),
              text: cr.outstanding <= 0 ? tr('You have no outstanding balance with HOLA.') : tr('HOLA will confirm your payments and update your statement.'),
            ),
          )
        else ...[
          HField(
            label: tr('Amount to pay (Rs)'),
            controller: amount,
            keyboard: TextInputType.number,
            icon: 'cash',
            helper: tr('Up to {amount}. You can pay part of it.', {'amount': rs(vm.payable)}),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 22),
          Text(tr('HOW WILL YOU PAY?'), style: T.eyebrow(context)),
          const SizedBox(height: 10),
          OptionTile(
            icon: 'truck',
            title: tr('Pay to the rider'),
            sub: tr('Hand the cash to the HOLA rider on your next delivery.'),
            on: vm.method == PayMethod.rider,
            onTap: () => _pick(vm, PayMethod.rider),
          ),
          const SizedBox(height: 10),
          OptionTile(
            icon: 'store',
            title: tr('Pay HOLA directly'),
            sub: tr('Cash at the HOLA office, or online transfer.'),
            on: vm.direct,
            onTap: () => _pick(vm, vm.direct ? vm.method : PayMethod.cash),
          ),
          if (vm.direct) ...[
            const SizedBox(height: 16),
            Seg(opts: [('cash', tr('Cash')), ('online', tr('Online'))], value: vm.method.name, onChanged: (v) => _pick(vm, PayMethod.values.byName(v))),
            const SizedBox(height: 14),
            if (vm.method == PayMethod.cash)
              _Note(tr('Take the cash to the HOLA office or give it to your sales officer. Your statement updates once HOLA counts it.'))
            else ...[
              HField(label: tr('Transaction ID'), hint: tr('From your bank, JazzCash or Easypaisa receipt'), controller: reference, icon: 'doc', onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              _Proof(path: vm.proofPath, onPick: () => _proof(context, vm), onClear: () => vm.setProof(null)),
              const SizedBox(height: 12),
              _Note(tr('HOLA finance checks the receipt. Your statement updates once it is confirmed.')),
            ],
          ] else ...[
            const SizedBox(height: 14),
            _Note(tr('The rider records the cash in the app and hands it to HOLA. Your statement updates once HOLA confirms it.')),
          ],
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  String _cta(PayMethod m) => switch (m) {
    PayMethod.rider => tr('Pay the rider'),
    PayMethod.cash => tr('I will pay in cash'),
    PayMethod.online => tr('Send receipt'),
  };

  void _pick(PayOutstandingViewModel vm, PayMethod m) {
    Sfx.tap();
    vm.setMethod(m);
  }

  Future<void> _proof(BuildContext context, PayOutstandingViewModel vm) async {
    final source = await showHSheet<ImageSource>(
      context,
      (ctx) => VStack(gap: 10, [
        SheetHead(tr('Payment proof'), sub: tr('A clear photo of the receipt, or a screenshot of the transfer.')),
        HButton(tr('Choose screenshot'), icon: 'grid', block: true, onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        HButton(tr('Take a photo'), icon: 'camera', block: true, kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx, ImageSource.camera)),
      ]),
    );
    if (source == null) return;
    final x = await ImagePicker().pickImage(source: source, maxWidth: 1800, imageQuality: 85);
    if (x != null) vm.setProof(x.path);
  }

  Future<void> _send(BuildContext context, PayOutstandingViewModel vm) async {
    final m = vm.method;
    final ok = await attempt(
      () => vm.submit(amount: _amount, reference: reference.text),
      success: switch (m) {
        PayMethod.rider => tr('Done. The rider will collect {amount} on your next delivery.', {'amount': rs(_amount)}),
        PayMethod.cash => tr('Noted. Pay {amount} at the HOLA office.', {'amount': rs(_amount)}),
        PayMethod.online => tr('Receipt sent. HOLA will confirm it.'),
      },
      icon: 'cash',
    );
    if (ok && context.mounted) Navigator.of(context).maybePop();
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HIcon('shield', size: 18, color: c.brandText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: T.sm(context).copyWith(color: c.ink)),
          ),
        ],
      ),
    );
  }
}

/// The receipt photo: a tap target when empty, a preview with "Change" once picked.
class _Proof extends StatelessWidget {
  const _Proof({required this.path, required this.onPick, required this.onClear});
  final String? path;
  final VoidCallback onPick, onClear;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tap(
      onTap: onPick,
      child: Container(
        height: path == null ? 120 : 220,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: path == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HIcon('camera', size: 28, color: c.brand),
                  const SizedBox(height: 8),
                  Text(tr('Add receipt or screenshot'), style: T.ttl(context)),
                  Text(tr('Required for online payments'), style: T.cap(context)),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(path!), fit: BoxFit.contain),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        tr('Change'),
                        style: const TextStyle(fontFamily: T.f, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
