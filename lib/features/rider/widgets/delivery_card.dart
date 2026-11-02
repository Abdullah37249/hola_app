import 'package:flutter/material.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/deliveries_view_model.dart';

/// Delivery summary: where, what, and the money involved.
class DeliveryCard extends StatelessWidget {
  final TradeOrder o;
  final Stop stop;
  final VoidCallback onTap;
  const DeliveryCard({super.key, required this.o, required this.stop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final live = o.status == OrderStatus.outForDelivery;
    final done = o.status == OrderStatus.delivered || o.status == OrderStatus.confirmed;
    final deliveredAt = o.at(OrderStatus.delivered);
    final money = !o.isCod ? tr('On credit') : done ? tr('Collected {amount}', {'amount': rs(o.cashCollected ?? o.total)}) : tr('Collect {amount}', {'amount': rs(o.total)});
    return HCard(
      onTap: onTap,
      border: live ? Border.all(color: c.brand, width: 1.5) : null,
      child: VStack(gap: 12, [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 52, height: 52, child: SalonArt(stop.salon.palette, photo: stop.salon.cover, n: 2, radius: 12, name: stop.salon.name)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stop.salon.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
              if (stop.place.isNotEmpty) Text(stop.place, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.sub(context)),
              const SizedBox(height: 6),
              StatusBadge(o.status),
            ]),
          ),
        ]),
        if (o.status == OrderStatus.failed && o.failReason != null)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HIcon('alert', size: 16, color: c.badInk),
            const SizedBox(width: 6),
            Expanded(child: Text(tr('{reason}. HOLA will re-assign it.', {'reason': tr(o.failReason!)}), style: T.sm(context).copyWith(color: c.badInk))),
          ]),
        Row(children: [
          Expanded(
            child: Text(
              '${o.code} · ${plural(o.units, 'unit')}${done && deliveredAt != null ? ' · ${dayLabel(deliveredAt, today)} ${fmtTime(deliveredAt)}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.sub(context),
            ),
          ),
          const SizedBox(width: 8),
          Text(money, style: T.sm(context).copyWith(color: o.isCod && !done ? c.accentInk : c.ink, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}
