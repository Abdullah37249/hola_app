import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/format.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../../chat/chat.dart';
import '../../profile/profile.dart';
import '../viewmodels/bookings_view_models.dart';
import '../viewmodels/customer_lookups.dart';
import '../viewmodels/discover_view_models.dart';
import '../widgets/salon_cards.dart';
import 'feedback_view.dart';

class CustomerProfile extends StatelessWidget {
  const CustomerProfile({super.key});
  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (c) => BookingsViewModel(c.read<SalonRepository>(), c.read<AuthRepository>(), c.read<BookingRepository>())),
      ChangeNotifierProvider(create: (c) => FeedbackViewModel(c.read<SalonRepository>(), c.read<AuthRepository>(), c.read<BookingRepository>(), c.read<EngagementRepository>())),
    ],
    child: const _ProfileBody(),
  );
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody();
  @override
  Widget build(BuildContext context) {
    final b = context.watch<BookingsViewModel>();
    final f = context.watch<FeedbackViewModel>();
    final saved = b.me?.favourites.length ?? 0;
    final open = f.items.where((x) => x.status == 'OPEN').length;
    return BandView(
      role: 'customer',
      children: [
        ...staggered([TopHead(title: tr('Profile')), const SizedBox(height: 16)]),
        // The account card sits across the header's edge, like Home.
        const BandMark(match: true, child: Reveal(i: 1, child: AccountCard())),
        ...staggered([
          const SizedBox(height: 16),
          Group(
            children: [
              MRow(
                icon: 'cal',
                title: tr('My bookings'),
                sub: b.upcoming.isEmpty ? tr('Nothing coming up') : tr('{n} coming up', {'n': b.upcoming.length}),
                onTap: () => context.read<SessionViewModel>().setTab('bookings'),
              ),
              MRow(icon: 'heart', tint: 1, title: tr('Saved salons'), sub: saved == 0 ? tr('None yet') : plural(saved, 'salon'), onTap: () => pushPage(context, const SavedSalonsPage())),
              MRow(icon: 'msg', tint: 2, title: tr('Messages'), sub: tr('Chats with salons'), onTap: () => pushPage(context, const CustomerChatsPage())),
              MRow(
                icon: 'alert',
                tint: 3,
                title: tr('Feedback & complaints'),
                sub: open > 0 ? tr('{n} waiting for a reply', {'n': open}) : tr('Tell a salon what went well or wrong'),
                onTap: () => pushPage(context, const MyFeedbackPage()),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const AppSettingsGroup(),
          const SizedBox(height: 22),
          Group(
            children: [
              MRow(
                icon: 'x',
                tint: 1,
                title: tr('Delete account'),
                titleColor: context.c.badInk,
                sub: tr('Remove your account from this phone'),
                onTap: () => pushPage(context, const DeleteAccountPage()),
              ),
            ],
          ),
          const SignOutButton(),
        ], 2),
      ],
    );
  }
}

/// Salons the customer saved with the heart.
class SavedSalonsPage extends StatelessWidget {
  const SavedSalonsPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => SavedViewModel(c.read<SalonRepository>(), c.read<AuthRepository>()),
    child: Consumer<SavedViewModel>(
      builder: (context, vm, _) {
        final list = vm.saved;
        return HPage(
          title: tr('Saved salons'),
          children: [
            if (list.isEmpty)
              HCard(
                child: EmptyState(
                  icon: 'heart',
                  title: tr('No saved salons'),
                  text: tr('Tap the heart on a salon to keep it here.'),
                  cta: HButton(
                    tr('Explore salons'),
                    icon: 'search',
                    small: true,
                    onTap: () {
                      exploreIntent.browse(null);
                      context.read<SessionViewModel>().setTab('explore');
                      popPage(context);
                    },
                  ),
                ),
              )
            else
              ...staggered([
                for (final s in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: s.isListed
                        ? SalonCard(s)
                        : HCard(
                            child: Row(
                              children: [
                                artThumb(s.palette, photo: s.cover, 48, name: s.name),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.name, style: T.ttl(context)),
                                      Text(tr('Not taking bookings right now'), style: T.cap(context)),
                                    ],
                                  ),
                                ),
                                IconBtn('heart', color: context.c.bad, onTap: () => vm.remove(s.id)),
                              ],
                            ),
                          ),
                  ),
              ]),
          ],
        );
      },
    ),
  );
}
