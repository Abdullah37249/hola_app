import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/bookings_view_models.dart';
import '../viewmodels/customer_lookups.dart';
import '../widgets/booking_card.dart';

class CustomerBookings extends StatelessWidget {
  const CustomerBookings({super.key});
  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider(create: (c) => BookingsViewModel(c.read<SalonRepository>(), c.read<AuthRepository>(), c.read<BookingRepository>()), child: const _BookingsBody());
}

class _BookingsBody extends StatelessWidget {
  const _BookingsBody();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookingsViewModel>();
    final up = vm.segment == 'up';
    final list = up ? vm.upcoming : vm.past;
    return BandView(
      role: 'customer',
      onRefresh: context.read<BookingRepository>().sync,
      children: [
        ...staggered([
          TopHead(title: tr('Bookings'), sub: vm.upcoming.isEmpty ? tr('Nothing coming up') : tr('{n} coming up', {'n': vm.upcoming.length})),
          const SizedBox(height: 16),
        ]),
        // The switch sits across the header's edge, at the same height as Home.
        BandMark(
          match: true,
          child: Reveal(
            i: 1,
            child: Seg(
              opts: [
                ('up', tr('Upcoming ({n})', {'n': vm.upcoming.length})),
                ('past', tr('Past ({n})', {'n': vm.past.length})),
              ],
              value: vm.segment,
              onChanged: vm.setSegment,
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (list.isEmpty)
          Reveal(
            i: 3,
            child: HCard(
              child: EmptyState(
                icon: 'cal',
                title: up ? tr('No upcoming bookings') : tr('No past bookings'),
                text: up ? tr('Find a salon and book your next visit in a few taps.') : tr('Your completed and cancelled visits show up here.'),
                cta: up
                    ? HButton(
                        tr('Find a salon'),
                        icon: 'search',
                        small: true,
                        onTap: () {
                          exploreIntent.browse(null);
                          context.read<SessionViewModel>().setTab('explore');
                        },
                      )
                    : null,
              ),
            ),
          )
        else
          ...staggered([for (final a in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: BookingCard(a))], 3),
      ],
    );
  }
}
