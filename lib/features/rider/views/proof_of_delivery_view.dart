import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/delivery_view_model.dart';
import '../widgets/signature_pad.dart';

/// Proof of delivery: who received it, their signature, and the cash (COD).
class ProofOfDeliveryView extends StatefulWidget {
  const ProofOfDeliveryView({super.key});
  @override
  State<ProofOfDeliveryView> createState() => _ProofOfDeliveryViewState();
}

class _ProofOfDeliveryViewState extends State<ProofOfDeliveryView> {
  late final DeliveryViewModel vm = context.read<DeliveryViewModel>();
  late final _name = TextEditingController(text: vm.recipient);
  late final _cash = TextEditingController(text: vm.cash);

  @override
  void dispose() {
    _name.dispose();
    _cash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DeliveryViewModel>();
    final o = vm.order;
    final c = context.c;
    if (o == null) return HPage(title: tr('Proof of delivery'), children: const []);
    final cashOk = !o.isCod || vm.cashValue == o.total;
    final ready = vm.recipient.trim().length >= 2 && vm.signed && cashOk && (!vm.needsPhoto || vm.photo != null);
    return HPage(
      title: tr('Proof of delivery'),
      footer: HButton(
        tr('Confirm delivery'),
        icon: 'check',
        kind: BtnKind.ok,
        block: true,
        onTap: !ready
            ? null
            : () async {
                final ok = await attempt(vm.deliver, success: tr('Delivered. The salon has been notified'), confetti: true);
                if (ok && context.mounted) Navigator.of(context).pop();
              },
      ),
      children: staggered([
        const SizedBox(height: 4),
        // What this handover is about, at a glance.
        HCard(
          gradient: o.isCod ? G.sun : null,
          color: o.isCod ? null : c.surface2,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${o.code} · ${plural(o.units, 'unit')}',
                      style: T.cap(context).copyWith(color: o.isCod ? Colors.white70 : c.muted, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(o.isCod ? tr('Collect {amount}', {'amount': rs(o.total)}) : tr('On HOLA credit'), style: T.h1(context).copyWith(color: o.isCod ? Colors.white : c.ink, fontSize: 26)),
                    ),
                    Text(o.isCod ? tr('Cash on delivery') : tr('No cash to collect'), style: T.cap(context).copyWith(color: o.isCod ? Colors.white70 : c.muted)),
                  ],
                ),
              ),
              HIcon(o.isCod ? 'cash' : 'check', size: 28, color: o.isCod ? Colors.white70 : c.ok),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // A photo of the order at the salon (HOLA requires it).
        if (vm.needsPhoto) ...[
          Text(
            tr('Photo of the delivery'),
            style: TextStyle(fontFamily: T.f, fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
          ),
          const SizedBox(height: 8),
          Tap(
            onTap: () async {
              final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
              if (x != null) vm.setPhoto(x.path);
            },
            child: Container(
              height: 170,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.line),
              ),
              child: vm.photo == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        HIcon('camera', size: 28, color: c.brand),
                        const SizedBox(height: 8),
                        Text(tr('Take a photo of the order at the salon'), style: T.sm(context)),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(vm.photo!), fit: BoxFit.cover),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                            child: Text(
                              tr('Retake'),
                              style: const TextStyle(fontFamily: T.f, fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        HField(label: tr('Received by'), hint: tr('Full name of the person receiving'), icon: 'user', controller: _name, onChanged: vm.setRecipient),
        if (o.isCod) ...[
          const SizedBox(height: 16),
          HField(
            label: tr('Cash collected'),
            hint: '${o.total}',
            icon: 'cash',
            controller: _cash,
            keyboard: TextInputType.number,
            onChanged: vm.setCash,
            helper: tr('Amount due: {amount}. Count it in front of the recipient.', {'amount': rs(o.total)}),
          ),
          if (vm.cash.isNotEmpty && !cashOk) ...[
            const SizedBox(height: 6),
            Text(tr('This must be exactly {amount}.', {'amount': rs(o.total)}), style: T.cap(context).copyWith(color: c.badInk)),
          ],
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                tr('Signature'),
                style: TextStyle(fontFamily: T.f, fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
              ),
            ),
            if (vm.strokes.isNotEmpty)
              GestureDetector(
                onTap: vm.clearSignature,
                child: Text(tr('Clear'), style: T.link(context)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SignaturePad(strokes: vm.strokes, onStart: vm.strokeStart, onUpdate: vm.strokeUpdate),
        const SizedBox(height: 12),
        Text(tr('By signing, the recipient confirms the items were received in good condition.'), style: T.cap(context)),
      ]),
    );
  }
}
