import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/ui.dart';

/// HOLA's warm offer colours (the same in light and dark).
const _promo = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFB547), Color(0xFFFF8A00), Color(0xFFF2650F)], stops: [0, .55, 1]);

/// A coupon HOLA sent the salon, shown as a promotion: eyebrow, offer,
/// "20% off … until 6 Nov", and a button to order with it.
class PromoCard extends StatelessWidget {
  const PromoCard(this.coupon, {super.key, required this.onUse, this.dim = false});
  final SalonCoupon coupon;
  final VoidCallback? onUse;

  /// Used or expired: shown greyed in the offers list.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final cp = coupon;
    final line = [
      if (cp.discountText.isNotEmpty) cp.discountText,
      if (cp.products.isNotEmpty) tr('on {what}', {'what': cp.products.take(2).join(', ')}),
    ].join(' ');
    // The one place the end date shows: top right.
    // The year only when it isn't this year: "11 Oct 2027" doesn't read as past.
    final u = cp.validUntil;
    final until = u == null ? null : tr('Valid until {date}', {'date': '${u.day} ${months[u.month - 1]}${u.year != DateTime.now().year ? ' ${u.year}' : ''}'});
    const white = Colors.white;
    return Opacity(
      opacity: dim ? .55 : 1,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: _promo,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x40FF8A00), blurRadius: 18, spreadRadius: -6, offset: Offset(0, 10))],
        ),
        child: Stack(
          children: [
            // Soft circles of light, like the offer artwork.
            Positioned(right: -40, top: -60, child: _glow(150)),
            Positioned(right: 40, bottom: -70, child: _glow(120)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Who it's from, and (once) until when.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (cp.campaign.isEmpty ? tr('HOLA offer') : cp.campaign).toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.eyebrow(context).copyWith(color: white.withValues(alpha: .85)),
                        ),
                      ),
                      if (until != null && !dim) ...[
                        const SizedBox(width: 8),
                        Text(
                          until,
                          style: T.cap(context).copyWith(color: white, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cp.title.isEmpty ? cp.code : cp.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: T.h3(context).copyWith(color: white),
                            ),
                            if (line.isNotEmpty)
                              Text(
                                line,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: T.sm(context).copyWith(color: white.withValues(alpha: .95)),
                              ),
                          ],
                        ),
                      ),
                      if (onUse != null && !dim) ...[
                        const SizedBox(width: 10),
                        Tap(
                          onTap: onUse,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: white, borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              tr('Use on my order'),
                              style: T.sm(context).copyWith(color: const Color(0xFFD9530B), fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // The code (or used/expired/starts), then any minimum.
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: white.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: white.withValues(alpha: .45)),
                        ),
                        child: Text(switch (cp.status) {
                          'USED' when cp.usedOnOrder.isNotEmpty && cp.usedAt != null => tr('Used on {code} · {date}', {
                            'code': cp.usedOnOrder,
                            'date': '${cp.usedAt!.day} ${months[cp.usedAt!.month - 1]}',
                          }),
                          'USED' when cp.usedOnOrder.isNotEmpty => tr('Used on {code}', {'code': cp.usedOnOrder}),
                          'USED' => tr('Already used'),
                          'RESERVED' when cp.reservedOnOrder.isNotEmpty => tr('Held for {code}', {'code': cp.reservedOnOrder}),
                          'RESERVED' => tr('Held for an order'),
                          'EXPIRED' => tr('Expired'),
                          'UPCOMING' when cp.validFrom != null => tr('Starts {date}', {'date': '${cp.validFrom!.day} ${months[cp.validFrom!.month - 1]}'}),
                          'UPCOMING' => tr('Coming soon'),
                          _ => tr('Code {code}', {'code': cp.code}),
                        }, style: T.cap(context).copyWith(color: white, fontWeight: FontWeight.w700, letterSpacing: .4)),
                      ),
                      if (cp.minOrder case final m? when m > 0) ...[
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            cp.products.isEmpty ? tr('Min. order {amount}', {'amount': rsShort(m)}) : tr('Min. spend {amount} on these products', {'amount': rsShort(m)}),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.cap(context).copyWith(color: white.withValues(alpha: .95), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .12)),
  );
}
