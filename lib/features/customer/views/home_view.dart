import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../../notifications/notifications.dart';
import '../viewmodels/customer_lookups.dart';
import '../viewmodels/discover_view_models.dart';
import '../widgets/salon_cards.dart';
import 'booking_detail_view.dart';

class CustomerHome extends StatelessWidget {
  const CustomerHome({super.key});
  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider(create: (c) => HomeViewModel(c.read<SalonRepository>(), c.read<BookingRepository>(), c.read<AuthRepository>()), child: const _HomeBody());
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  void _browse(BuildContext context, String? cat) {
    exploreIntent.browse(cat);
    context.read<SessionViewModel>().setTab('explore');
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    final c = context.c;
    final next = vm.nextVisit;
    final review = vm.toReview;
    final live = vm.live;
    final near = vm.nearYou;
    final city = vm.me?.city.trim() ?? '';
    return BandView(
      role: 'customer',
      children: [
        ...staggered([
          TopHead(eyebrow: dLabel(today), title: '${vm.greeting},\n${vm.me?.firstName ?? ''}', actions: const [NotificationBell()]),
          const SizedBox(height: 18),
          Tap(
            onTap: () {
              exploreIntent.search();
              context.read<SessionViewModel>().setTab('explore');
            },
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), boxShadow: c.lift),
              child: Row(
                children: [
                  HIcon('search', size: 20, color: c.subtle),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('Search salons, services or areas'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.body(context).copyWith(color: c.subtle),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (next != null) ...[const SizedBox(height: 22), _NextVisit(next)],
          if (review != null) ...[const SizedBox(height: 12), _ReviewNudge(review)],
        ]),
        const BandMark(),
        ...staggered([
          const SizedBox(height: 28),
          SecHead(tr('Browse by service')),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (var i = 0; i < serviceCategories.length; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == serviceCategories.length - 1 ? 0 : 6),
                    child: CategoryTile(serviceCategories[i], i, onTap: () => _browse(context, serviceCategories[i])),
                  ),
              ],
            ),
          ),
        ]),
        if (live.isEmpty) ...[
          const SizedBox(height: 28),
          Reveal(
            i: 5,
            child: HCard(
              child: EmptyState(
                icon: 'store',
                title: city.isEmpty ? tr('No salons on HOLA yet') : tr('No salons on HOLA in {city} yet', {'city': city}),
                text: tr('Salons appear here as soon as they join HOLA. Check back soon.'),
              ),
            ),
          ),
        ] else ...[
          if (vm.favourites.isNotEmpty) ..._row(context, tr('Your salons'), vm.favourites, 5),
          if (near.isNotEmpty) ..._row(context, tr('Near you in {city}', {'city': city}), near, 6),
          ..._row(context, tr('New on HOLA'), vm.newest, 7),
          if (vm.topRated.isNotEmpty) ...[
            const SizedBox(height: 28),
            Reveal(
              i: 8,
              child: SecHead(tr('Top rated'), action: tr('See all'), onAction: () => _browse(context, null)),
            ),
            const SizedBox(height: 12),
            ...staggered([for (final s in vm.topRated.take(3)) Padding(padding: const EdgeInsets.only(bottom: 24), child: SalonCard(s))], 9),
          ],
        ],
      ],
    );
  }

  List<Widget> _row(BuildContext context, String title, List<Salon> list, int i) => [
    const SizedBox(height: 28),
    Reveal(
      i: i,
      child: SecHead(title, action: tr('See all'), onAction: () => _browse(context, null)),
    ),
    const SizedBox(height: 12),
    Reveal(
      i: i,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final s in list) Padding(padding: const EdgeInsets.only(right: 14), child: SalonMini(s))],
        ),
      ),
    ),
  ];
}

class _NextVisit extends StatelessWidget {
  final Appointment a;
  const _NextVisit(this.a);
  @override
  Widget build(BuildContext context) {
    final vm = context.read<HomeViewModel>();
    final s = vm.salon(a.salonId);
    const w = TextStyle(color: Colors.white);
    final dim = Colors.white.withValues(alpha: .85);
    return HCard(
      onTap: () => pushPage(context, BookingDetailPage(id: a.id)),
      padding: EdgeInsets.zero,
      radius: 20,
      gradient: G.sun,
      shadow: const [BoxShadow(color: Color(0x660B3566), blurRadius: 30, spreadRadius: -12, offset: Offset(0, 16))],
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tr('YOUR NEXT VISIT'), style: T.eyebrow(context).copyWith(color: Colors.white.withValues(alpha: .8))),
                    ),
                    StatusBadge(a.status, label: customerStatusLabels[a.status] == null ? null : tr(customerStatusLabels[a.status]!)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 62,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: .3)),
                      ),
                      child: Column(
                        children: [
                          Text(days[weekday0(a.startsAt)], style: T.cap(context).merge(w)),
                          Text('${a.startsAt.day}', style: T.h1(context).merge(w).copyWith(height: 1.1)),
                          Text(months[a.startsAt.month - 1], style: T.cap(context).merge(w)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s?.name ?? tr('Salon'), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h2(context).merge(w)),
                          Text(
                            a.serviceNames.join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.sm(context).copyWith(color: dim),
                          ),
                          Text(
                            '${fmtTime(a.startsAt)} · ${vm.personName(a.staffId)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.sm(context).copyWith(color: dim),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewNudge extends StatelessWidget {
  final Appointment a;
  const _ReviewNudge(this.a);
  @override
  Widget build(BuildContext context) {
    final vm = context.read<HomeViewModel>();
    final s = vm.salon(a.salonId);
    return HCard(
      onTap: () => pushPage(context, BookingDetailPage(id: a.id)),
      child: Row(
        children: [
          artThumb(s?.palette ?? 0, photo: s?.cover, 46, radius: 12, name: s?.name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s == null ? tr('How was your visit?') : tr('How was {salon}?', {'salon': s.name}), maxLines: 2, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                Text(tr('Your review helps others choose.'), style: T.sm(context).copyWith(color: context.c.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          HIcon('star', size: 22, color: context.c.accent),
        ],
      ),
    );
  }
}
