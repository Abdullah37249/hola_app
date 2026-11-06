import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/ui.dart';

/// Warm offer colours (the same in light and dark), as on HOLA's promotions.
const offerGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFB547), Color(0xFFFF8A00), Color(0xFFF2650F)], stops: [0, .55, 1]);

/// The offer's colour for text on a light card.
const offerInk = Color(0xFFD9530B);

/// "20% off" or "Rs 500 off".
String offText(ServiceOffer o) => o.isPercent ? tr('{n}% off', {'n': o.discountValue}) : tr('{amount} off', {'amount': rs(o.discountValue)});

/// "6 Nov".
String dayMonth(DateTime d) => '${d.day} ${months[d.month - 1]}';

/// A salon's offer as customers see it: salon, "25% off Facial", the price
/// before and after, until when, and a button to book it.
class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.offer, required this.salonName, required this.serviceName, required this.price, required this.use, this.heldOn = '', this.onBook});
  final ServiceOffer offer;
  final String salonName, serviceName;

  /// The service's normal price.
  final int price;

  /// [OfferUse] for this customer, and the booking holding it.
  final String use;
  final String heldOn;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final o = offer;
    final free = use == OfferUse.none;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: offerGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x40FF8A00), blurRadius: 18, spreadRadius: -6, offset: Offset(0, 10))],
      ),
      child: Stack(
        children: [
          Positioned(right: -40, top: -60, child: _glow(150)),
          Positioned(right: 40, bottom: -70, child: _glow(120)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        salonName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.eyebrow(context).copyWith(color: white.withValues(alpha: .85)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tr('Until {date}', {'date': dayMonth(o.lastDay)}),
                      style: T.cap(context).copyWith(color: white, fontWeight: FontWeight.w600),
                    ),
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
                            '${offText(o)} · $serviceName',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: T.h3(context).copyWith(color: white),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: rs(price),
                                  style: TextStyle(decoration: TextDecoration.lineThrough, decorationColor: white, color: white.withValues(alpha: .8)),
                                ),
                                const TextSpan(text: '   '),
                                TextSpan(
                                  text: rs(price - o.discountOn(price)),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            style: T.body(context).copyWith(color: white),
                          ),
                        ],
                      ),
                    ),
                    if (onBook != null && free) ...[
                      const SizedBox(width: 10),
                      Tap(
                        onTap: onBook,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(color: white, borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            tr('Book'),
                            style: T.sm(context).copyWith(color: offerInk, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (!free) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: white.withValues(alpha: .45)),
                    ),
                    child: Text(
                      use == OfferUse.used
                          ? tr('You have already used this offer')
                          : heldOn.isEmpty
                          ? tr('Held for one of your bookings')
                          : tr('Held for {code}', {'code': heldOn}),
                      style: T.cap(context).copyWith(color: white, fontWeight: FontWeight.w700, letterSpacing: .4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .12)),
  );
}
