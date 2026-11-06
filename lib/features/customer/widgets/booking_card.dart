import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../views/booking_detail_view.dart';
import '../views/booking_flow_view.dart';
import 'salon_cards.dart';

/// Customer-facing status badge (uses customer wording where it differs).
class CustomerStatus extends StatelessWidget {
  final String status;
  const CustomerStatus(this.status, {super.key});
  @override
  Widget build(BuildContext context) => StatusBadge(status, label: customerStatusLabels[status] == null ? null : tr(customerStatusLabels[status]!));
}

class BookingCard extends StatelessWidget {
  final Appointment a;
  const BookingCard(this.a, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = context.read<SalonRepository>().salon(a.salonId);
    return HCard(
      onTap: () => pushPage(context, BookingDetailPage(id: a.id)),
      child: VStack([
        Row(
          children: [
            Expanded(
              child: Text(
                '${dayLabel(a.startsAt, today)} · ${fmtTime(a.startsAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.sm(context).copyWith(color: c.muted, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            CustomerStatus(a.status),
          ],
        ),
        Row(
          children: [
            artThumb(s?.palette ?? 0, photo: s?.cover, 52, radius: 10, name: s?.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s?.name ?? tr('Salon'), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                  Text(
                    a.serviceNames.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.sm(context).copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(rsShort(a.price), style: T.ttl(context)),
          ],
        ),
        // A past visit: book the same again in one tap.
        if (ApptStatus.finished.contains(a.status) && s != null && s.isListed) ...[
          const HDivider(),
          Tap(
            onTap: () => pushPage(context, rebookPage(context.read<SalonRepository>(), a)),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr('Same services, same professional'), style: T.sm(context).copyWith(color: c.muted)),
                ),
                HIcon('again', size: 16, color: c.brandText),
                const SizedBox(width: 6),
                Text(tr('Book again'), style: T.link(context)),
              ],
            ),
          ),
        ],
        if (a.status == ApptStatus.completed && !a.reviewed) ...[
          const HDivider(),
          Row(
            children: [
              Expanded(
                child: Text(tr('How was your visit?'), style: T.sm(context).copyWith(color: c.muted)),
              ),
              Text(tr('Rate it'), style: T.link(context)),
              const SizedBox(width: 2),
              HIcon('chev', size: 16, color: c.brandText),
            ],
          ),
        ],
      ]),
    );
  }
}
