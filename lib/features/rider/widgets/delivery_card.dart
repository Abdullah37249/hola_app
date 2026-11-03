import 'package:flutter/material.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/deliveries_view_model.dart';

/// One assigned order: the salon, its full address and number, what to
/// collect, and the next step (pick up, or navigate once picked up).
class DeliveryCard extends StatelessWidget {
  final TradeOrder o;
  final Stop stop;
  final VoidCallback onTap;
  final VoidCallback? onPickUp, onNavigate, onCall;

  /// The salon also pays its credit balance to the rider on this visit.
  final CreditCollection? collect;
  const DeliveryCard({super.key, required this.o, required this.stop, required this.onTap, this.onPickUp, this.onNavigate, this.onCall, this.collect});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final live = o.status == OrderStatus.outForDelivery;
    final done = o.status == OrderStatus.delivered || o.status == OrderStatus.confirmed;
    final deliveredAt = o.at(OrderStatus.delivered);
    final money = !o.isCod
        ? tr('On credit')
        : done
        ? tr('Collected {amount}', {'amount': rs(o.cashCollected ?? o.total)})
        : tr('Collect {amount}', {'amount': rs(o.total)});
    final address = stop.fullAddress;
    Widget line(String icon, String text, {Widget? trailing}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: HIcon(icon, size: 16, color: c.muted),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: T.sm(context))),
        ?trailing,
      ],
    );
    return HCard(
      onTap: onTap,
      border: live ? Border.all(color: c.brand, width: 1.5) : null,
      child: VStack(gap: 12, [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: SalonArt(stop.salon.palette, photo: stop.salon.cover, n: 2, radius: 12, name: stop.salon.name),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stop.salon.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.h3(context)),
                  Text('${o.code} · ${plural(o.units, 'unit')}', style: T.cap(context)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(o.status),
          ],
        ),
        if (!done) ...[
          line(
            'pin',
            address.isEmpty ? tr('No address on file. Call the salon.') : address,
            trailing: stop.location == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ToneBadge(tr('GPS'), tone: 'ok'),
                  ),
          ),
          if (stop.phone.isNotEmpty)
            line(
              'phone',
              [stop.ownerName, stop.phone].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
              trailing: onCall == null
                  ? null
                  : GestureDetector(
                      onTap: onCall,
                      child: Text(tr('Call'), style: T.link(context)),
                    ),
            ),
        ],
        if (o.status == OrderStatus.failed && o.failReason != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HIcon('alert', size: 16, color: c.badInk),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr('{reason}. HOLA will re-assign it.', {'reason': tr(o.failReason!)}), style: T.sm(context).copyWith(color: c.badInk)),
              ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                done && deliveredAt != null
                    ? tr('Delivered {day} {time}', {'day': dayLabel(deliveredAt, today), 'time': fmtTime(deliveredAt)})
                    : (o.isCod ? tr('Cash on delivery') : tr('HOLA credit')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.sub(context),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              money,
              style: T.sm(context).copyWith(color: o.isCod && !done ? c.accentInk : c.ink, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (collect case final cc?)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                HIcon('cash', size: 18, color: c.accentInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Also collect {amount} credit payment ({code})', {'amount': rs(cc.amount), 'code': cc.code}),
                    style: T.sm(context).copyWith(color: c.accentInk, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        if (o.status == OrderStatus.dispatched && onPickUp != null) HButton(tr('Picked up'), icon: 'box', block: true, onTap: onPickUp),
        if (live && onNavigate != null) HButton(tr('Start navigation'), icon: 'nav', block: true, onTap: onNavigate),
      ]),
    );
  }
}
