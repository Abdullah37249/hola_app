import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/trade_view_models.dart';
import '../widgets/promo_card.dart';
import 'new_order_page.dart';

/// Every offer HOLA sent this salon: usable ones first, then used/expired.
class OffersPage extends StatelessWidget {
  const OffersPage({super.key, required this.salonId});
  final String salonId;
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => SalonOrdersViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), salonId),
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonOrdersViewModel>();
        final all = context.read<TradeRepository>().coupons(salonId);
        final live = all.where((c) => c.available).toList(), gone = all.where((c) => !c.available).toList();
        return HPage(
          title: tr('Offers from HOLA'),
          onRefresh: () => context.read<TradeRepository>().syncCoupons(salonId),
          children: staggered([
            const SizedBox(height: 8),
            Text(tr('Coupons HOLA sent your salon. Tap Order to use one on a product order.'), style: T.sm(context).copyWith(color: context.c.muted)),
            const SizedBox(height: 16),
            if (all.isEmpty)
              HCard(
                child: EmptyState(icon: 'sparkle', title: tr('No offers right now'), text: tr('When HOLA sends your salon a coupon, it shows here and you get a notification.')),
              )
            else ...[
              for (final cp in live)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PromoCard(
                    cp,
                    onUse: vm.salon?.isActive == true ? () => pushPage(context, NewOrderPage(salonId: salonId, coupon: cp.code)) : null,
                  ),
                ),
              if (gone.isNotEmpty) ...[
                const SizedBox(height: 12),
                SecHead(tr('Coming up, held, used or expired')),
                if (gone.any((c) => c.reserved)) ...[
                  const SizedBox(height: 6),
                  Text(tr('A held coupon is on an order that hasn’t been delivered yet. If that order is cancelled, you can use it again.'), style: T.sm(context).copyWith(color: context.c.muted)),
                ],
                const SizedBox(height: 12),
                for (final cp in gone) Padding(padding: const EdgeInsets.only(bottom: 12), child: PromoCard(cp, onUse: null, dim: true)),
              ],
            ],
          ]),
        );
      },
    ),
  );
}
