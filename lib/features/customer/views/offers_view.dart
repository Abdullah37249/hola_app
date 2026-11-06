import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/mvvm/repo_view_model.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/customer_lookups.dart';
import '../widgets/offer_card.dart';
import 'salon_view.dart';

/// A running offer as a card; "Book" opens the salon with that service picked.
Widget offerCardOf(BuildContext context, CustomerLookups vm, ServiceOffer o) {
  final svc = vm.serviceInfo(o.serviceId);
  return OfferCard(
    offer: o,
    salonName: vm.salonName(o.salonId),
    serviceName: svc?.name ?? o.serviceName,
    price: svc?.price ?? o.servicePrice,
    use: vm.offerUse(o),
    heldOn: vm.offerHeldOn(o),
    onBook: () => pushPage(context, SalonPage(id: o.salonId, select: o.serviceId)),
  );
}

class _OffersViewModel extends RepoViewModel with CustomerLookups {
  _OffersViewModel(this.salons, this.auth) : super(salons);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  List<ServiceOffer> get offers => offersLive();
}

/// Every running offer at the salons this customer can see.
class CustomerOffersPage extends StatelessWidget {
  const CustomerOffersPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => _OffersViewModel(c.read<SalonRepository>(), c.read<AuthRepository>()),
    child: Builder(
      builder: (context) {
        final vm = context.watch<_OffersViewModel>();
        final xs = vm.offers;
        return HPage(
          title: tr('Offers'),
          children: [
            const SizedBox(height: 8),
            if (xs.isEmpty)
              HCard(
                child: EmptyState(icon: 'sparkle', title: tr('No offers right now'), text: tr('Salons’ discounts on their services show here while they run.')),
              ),
            for (final (i, o) in xs.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Reveal(i: i, child: offerCardOf(context, vm, o)),
              ),
          ],
        );
      },
    ),
  );
}
