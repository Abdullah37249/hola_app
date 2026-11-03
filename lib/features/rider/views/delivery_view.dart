import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/maps.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/deliveries_view_model.dart';
import '../viewmodels/delivery_view_model.dart';
import '../widgets/signature_pad.dart';
import 'proof_of_delivery_view.dart';

/// Rings a number in the phone's dialler.
Future<void> callPhone(String phone) async {
  final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));
  if (!await launchUrl(uri)) Fx.toast(tr("Couldn't open the dialler"), icon: 'alert', tone: 'bad');
}

/// Opens Google Maps with directions to the salon (its GPS when saved,
/// otherwise its written address).
Future<void> navigateTo(Stop stop) async {
  final address = [stop.salon.name, stop.fullAddress].where((x) => x.isNotEmpty).join(', ');
  if (stop.location == null && stop.fullAddress.isEmpty && stop.mapsUrl == null) {
    Fx.toast(tr('This salon has no address yet. Call them for directions.'), icon: 'alert', tone: 'bad');
    return;
  }
  Sfx.tap();
  if (!await startNavigation(at: stop.location, address: address, link: stop.mapsUrl)) Fx.toast(tr("Couldn't open Google Maps"), icon: 'alert', tone: 'bad');
}

/// One delivery: where to go, who to call, what to hand over, and the next step.
class DeliveryPage extends StatelessWidget {
  final String id;
  const DeliveryPage({super.key, required this.id});
  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider(create: (c) => DeliveryViewModel(id, c.read<TradeRepository>(), c.read<SalonRepository>(), c.read<AuthRepository>()), child: const _Delivery());
}

class _Delivery extends StatelessWidget {
  const _Delivery();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DeliveryViewModel>();
    final o = vm.order, stop = vm.stop;
    if (o == null || stop == null) {
      return HPage(
        title: tr('Delivery'),
        children: [
          const SizedBox(height: 60),
          EmptyState(icon: 'box', title: tr('Delivery not found'), text: tr('It may have been cancelled by HOLA.')),
        ],
      );
    }
    final c = context.c;
    final ownerName = stop.ownerName, ownerPhone = stop.ownerPhone;
    final done = o.status == OrderStatus.delivered || o.status == OrderStatus.confirmed;
    return HPage(
      title: o.code,
      hero: Reveal(
        child: SalonArt(stop.salon.palette, photo: stop.salon.cover, height: 150 + MediaQuery.paddingOf(context).top, radius: 0, name: stop.salon.name),
      ),
      footer: _footer(context, vm, o),
      children: staggered([
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(stop.salon.name, style: T.h2(context))],
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(o.status),
          ],
        ),
        const SizedBox(height: 16),
        if (o.status == OrderStatus.failed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: HCard(
              color: c.badSoft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HIcon('alert', size: 20, color: c.badInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tr('Not delivered: {reason}. HOLA will re-assign this order.', {'reason': tr(o.failReason ?? '')}), style: T.sm(context).copyWith(color: c.badInk)),
                  ),
                ],
              ),
            ),
          ),
        // Where to go: full address, GPS, and directions once picked up.
        HCard(
          child: VStack(gap: 12, [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: HIcon('pin', size: 20, color: c.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Delivery address'), style: T.cap(context)),
                      Text(stop.fullAddress.isEmpty ? tr('No address on file. Call the salon.') : stop.fullAddress, style: T.ttl(context)),
                      const SizedBox(height: 4),
                      Text(
                        stop.location == null ? tr('No GPS saved: Maps will search the address') : tr('GPS {where}', {'where': stop.location!.label}),
                        style: T.cap(context).copyWith(color: stop.location == null ? c.muted : c.ok),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (o.status == OrderStatus.outForDelivery) HButton(tr('Start navigation'), icon: 'nav', block: true, onTap: () => navigateTo(stop)),
          ]),
        ),
        const SizedBox(height: 14),
        Group(
          children: [
            if (ownerName.isNotEmpty || ownerPhone.isNotEmpty)
              MRow(
                icon: 'user',
                title: ownerName.isEmpty ? tr('Salon owner') : ownerName,
                sub: ownerPhone.isEmpty ? tr('Salon owner') : '${tr('Salon owner')} · $ownerPhone',
                trailing: ownerPhone.isEmpty ? null : IconBtn('phone', onTap: () => _call(ownerPhone)),
                onTap: ownerPhone.isEmpty ? null : () => _contactSheet(context, ownerName.isEmpty ? stop.salon.name : ownerName, ownerPhone),
              ),
            if (stop.salon.phone.isNotEmpty && stop.salon.phone != ownerPhone)
              MRow(
                icon: 'store',
                title: tr('Salon phone'),
                sub: stop.salon.phone,
                trailing: IconBtn('phone', onTap: () => _call(stop.salon.phone)),
                onTap: () => _contactSheet(context, stop.salon.name, stop.salon.phone),
              ),
            MRow(
              icon: 'cash',
              title: !o.isCod
                  ? tr('On HOLA credit, no cash')
                  : done
                  ? tr('Collected {amount}', {'amount': rs(o.cashCollected ?? o.total)})
                  : tr('Collect {amount} cash', {'amount': rs(o.total)}),
              sub: o.isCod ? tr('Cash on delivery') : tr('Nothing to collect'),
            ),
          ],
        ),
        // The salon also pays off its HOLA credit through the rider.
        if (vm.creditCollection case final cc?) ...[
          const SizedBox(height: 14),
          HCard(
            color: c.accentSoft,
            child: VStack(gap: 10, [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HIcon('cash', size: 20, color: c.accentInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Also collect {amount} credit payment', {'amount': rs(cc.amount)}), style: T.ttl(context).copyWith(color: c.accentInk)),
                        Text(tr('{code} · The salon is paying off its HOLA balance. Hand it over with your cash.', {'code': cc.code}), style: T.sm(context).copyWith(color: c.accentInk)),
                      ],
                    ),
                  ),
                ],
              ),
              HButton(tr('Record credit payment'), icon: 'cash', block: true, onTap: () => _collectCredit(context, vm, cc)),
            ]),
          ),
        ],
        const SizedBox(height: 24),
        SecHead(tr('Items · {units}', {'units': plural(o.units, 'unit')})),
        const SizedBox(height: 12),
        HCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < o.lines.length; i++) ...[
                if (i > 0) const HDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(10)),
                        alignment: Alignment.center,
                        child: Text(
                          '×${o.lines[i].qty + o.lines[i].freeQty}',
                          style: T.sm(context).copyWith(color: c.brandText, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.lines[i].name, style: T.ttl(context)),
                            if (o.lines[i].freeQty > 0) Text(tr('{qty} + {n} free', {'qty': o.lines[i].qty, 'n': o.lines[i].freeQty}), style: T.cap(context).copyWith(color: c.ok)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (o.notes.isNotEmpty) ...[
          const SizedBox(height: 14),
          HCard(
            color: c.surface2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HIcon('doc', size: 18, color: c.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(o.notes, style: T.sm(context))),
              ],
            ),
          ),
        ],
        if (done) ...[
          const SizedBox(height: 24),
          SecHead(tr('Proof of delivery')),
          const SizedBox(height: 12),
          HCard(
            child: VStack(gap: 10, [
              if (o.at(OrderStatus.delivered) case final at?) KV(tr('Delivered'), '${dayLabel(at, today)}, ${fmtTime(at)}'),
              KV(tr('Received by'), o.recipientName ?? '—'),
              if (o.isCod) KV(tr('Cash collected'), rs(o.cashCollected ?? 0)),
              if (o.deliveredWhere case final w?) KV(tr('Location'), w.label) else KV(tr('Location'), tr('Not recorded')),
              if (o.signature != null) SignatureView(o.signature!),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget? _footer(BuildContext context, DeliveryViewModel vm, TradeOrder o) {
    switch (o.status) {
      case OrderStatus.dispatched:
        // Collected from HOLA's warehouse: now on the way to the salon.
        return HButton(
          tr('Picked up'),
          icon: 'box',
          block: true,
          onTap: () => attempt(vm.start, success: tr('Picked up. Tap Start navigation to go'), icon: 'truck'),
        );
      case OrderStatus.outForDelivery:
        // Primary action first and full width; the exception path below it.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HButton(
              tr('Deliver and get proof'),
              icon: 'check',
              kind: BtnKind.ok,
              block: true,
              onTap: () => pushPage(context, ChangeNotifierProvider.value(value: vm, child: const ProofOfDeliveryView())),
            ),
            const SizedBox(height: 4),
            HButton(tr("Couldn't deliver"), kind: BtnKind.ghost, small: true, block: true, onTap: () => _failSheet(context, vm)),
          ],
        );
      default:
        return null;
    }
  }

  static Future<void> _call(String phone) => callPhone(phone);

  static void _contactSheet(BuildContext context, String name, String phone) => showHSheet(
    context,
    (ctx) => VStack(gap: 14, [
      SheetHead(name, sub: phone),
      HButton(
        tr('Call'),
        icon: 'phone',
        block: true,
        onTap: () {
          Navigator.pop(ctx);
          _call(phone);
        },
      ),
      HButton(
        tr('Copy number'),
        kind: BtnKind.secondary,
        block: true,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: phone));
          if (ctx.mounted) Navigator.pop(ctx);
          Sfx.tap();
          Fx.toast(tr('Number copied'));
        },
      ),
    ]),
  );

  static Future<void> _failSheet(BuildContext context, DeliveryViewModel vm) async {
    const reasons = ['Salon closed', 'Owner not available', 'Refused the order', 'Wrong address', 'Cash not ready'];
    String? pick;
    final other = TextEditingController();
    final reason = await showHSheet<String>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final text = pick == 'Other' ? other.text.trim() : pick;
          return VStack(gap: 14, [
            SheetHead(tr("Why couldn't you deliver?"), sub: tr('HOLA and the salon will be told, and the order will be re-assigned.')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in [...reasons, 'Other']) HChip(tr(r), on: pick == r, onTap: () => set(() => pick = r)),
              ],
            ),
            if (pick == 'Other') HField(label: tr('What happened?'), hint: tr('e.g. Road closed near the salon'), controller: other, onChanged: (_) => set(() {})),
            HButton(tr('Report failed delivery'), kind: BtnKind.danger, block: true, onTap: text == null || text.length < 3 ? null : () => Navigator.pop(ctx, text)),
          ]);
        },
      ),
    );
    other.dispose();
    if (reason != null) await attempt(() => vm.fail(reason), success: tr('Reported. HOLA will re-assign it'), icon: 'alert');
  }
}

/// The rider counts the salon's credit payment; less than asked is fine.
Future<void> _collectCredit(BuildContext context, DeliveryViewModel vm, CreditCollection cc) async {
  final v = await askText(
    context,
    title: tr('Credit payment {code}', {'code': cc.code}),
    body: tr('The salon is paying {amount}. Enter the cash you actually took.', {'amount': rs(cc.amount)}),
    label: tr('Cash taken (Rs)'),
    hint: '${cc.amount}',
    confirm: tr('Record payment'),
    minLength: 1,
    multiline: false,
    keyboard: TextInputType.number,
  );
  if (v == null) return;
  final n = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  await attempt(() => vm.collectCredit(n), success: tr('Recorded {amount}. Hand it to HOLA with your cash.', {'amount': rs(n)}), icon: 'cash');
}
