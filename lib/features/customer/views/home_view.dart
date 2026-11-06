import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../../notifications/notifications.dart';
import 'offers_view.dart';
import '../viewmodels/customer_lookups.dart';
import '../viewmodels/discover_view_models.dart';
import '../widgets/salon_cards.dart';
import 'booking_detail_view.dart';

class CustomerHome extends StatelessWidget {
  const CustomerHome({super.key});
  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider(create: (c) => HomeViewModel(c.read<SalonRepository>(), c.read<BookingRepository>(), c.read<AuthRepository>(), c.read<EngagementRepository>()), child: const _HomeBody());
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
    final search = Tap(
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
    );
    return BandView(
      role: 'customer',
      onRefresh: vm.syncSalons,
      children: [
        ...staggered([
          TopHead(eyebrow: dLabel(today), title: '${vm.greeting},\n${vm.me?.firstName ?? ''}', oneLine: true, actions: const [NotificationBell()]),
        ]),
        const SizedBox(height: 18),
        // The search bar sits across the header's edge, at the same height as
        // every other screen; the next visit follows on the page.
        BandMark(match: true, child: Reveal(i: 1, child: search)),
        if (next != null) ...[const SizedBox(height: 22), Reveal(i: 2, child: _NextVisit(next))],
        // Salons' running offers, swiped through; all of them on their own page.
        if (vm.offers case final offers when offers.isNotEmpty) ...[
          const SizedBox(height: 28),
          Reveal(
            i: 3,
            child: SecHead(tr('Offers'), action: offers.length > 1 ? tr('See all') : null, onAction: () => pushPage(context, const CustomerOffersPage())),
          ),
          const SizedBox(height: 12),
          Reveal(
            i: 3,
            child: offers.length == 1
                ? offerCardOf(context, vm, offers.first)
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final o in offers)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 12),
                            child: SizedBox(width: MediaQuery.sizeOf(context).width - 72, child: offerCardOf(context, vm, o)),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
        ...staggered([
          const SizedBox(height: 28),
          SecHead(tr('Browse by service')),
          const SizedBox(height: 14),
          // Every category at a glance: a grid of two rows, four across.
          Column(
            children: [
              for (var row = 0; row * 4 < serviceCategories.length; row++)
                Padding(
                  padding: EdgeInsets.only(top: row == 0 ? 0 : 16),
                  child: Row(
                    children: [
                      for (var i = row * 4; i < row * 4 + 4; i++)
                        Expanded(
                          child: i < serviceCategories.length ? Center(child: CategoryTile(serviceCategories[i], i, onTap: () => _browse(context, serviceCategories[i]))) : const SizedBox(),
                        ),
                    ],
                  ),
                ),
            ],
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
          if (review != null) ...[const SizedBox(height: 24), Reveal(i: 6, child: _ReviewNudge(review))],
        ] else ...[
          if (vm.favourites.isNotEmpty) ..._row(context, tr('Your salons'), vm.favourites, 5),
          if (near.isNotEmpty) ..._row(context, tr('Near you in {city}', {'city': city}), near, 6),
          // A finished visit not rated yet; gone once it's rated.
          if (review != null) ...[const SizedBox(height: 24), Reveal(i: 6, child: _ReviewNudge(review))],
          ..._row(context, tr('New on HOLA'), vm.newest, 7),
          if (vm.topRated.isNotEmpty) ...[
            const SizedBox(height: 28),
            Reveal(
              i: 8,
              child: SecHead(tr('Top rated salons'), action: tr('See all'), onAction: () => _browse(context, null)),
            ),
            const SizedBox(height: 12),
            ...staggered([for (final s in vm.topRated) Padding(padding: const EdgeInsets.only(bottom: 24), child: SalonCard(s))], 9),
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
          children: [for (final s in list) Padding(padding: const EdgeInsetsDirectional.only(end: 14), child: SalonMini(s))],
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
      radius: 22,
      // Calm brand blue: stands apart from the page without glaring.
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1F5BC2), Color(0xFF15418F), Color(0xFF0E2D66)], stops: [0, .55, 1]),
      border: Border.all(color: const Color(0x33FFFFFF), width: .8),
      shadow: const [BoxShadow(color: Color(0x552F80FF), blurRadius: 28, spreadRadius: -12, offset: Offset(0, 12))],
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: const CustomPaint(painter: _Arches()),
            ),
          ),
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
                    // White pill, like the date tag on HOLA's posters.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(color: Color(0xFF15418F), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            customerStatusLabels[a.status] == null ? (statusLabels[a.status]?.$1 ?? a.status) : tr(customerStatusLabels[a.status]!),
                            style: T.cap(context).copyWith(color: const Color(0xFF15418F), fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 60,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: .28)),
                      ),
                      child: Column(
                        children: [
                          Text(days[weekday0(a.startsAt)].toUpperCase(), style: T.eyebrow(context).copyWith(color: dim, letterSpacing: 1.2, height: 1.2)),
                          Text('${a.startsAt.day}', style: T.h1(context).merge(w).copyWith(fontSize: 26, height: 1.15)),
                          Text(months[a.startsAt.month - 1].toUpperCase(), style: T.eyebrow(context).copyWith(color: dim, letterSpacing: 1.2, height: 1.2)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s?.name ?? tr('Salon'), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h3(context).merge(w).copyWith(fontSize: 18)),
                          const SizedBox(height: 2),
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
                            style: T.sm(context).copyWith(color: Colors.white, fontWeight: FontWeight.w600),
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

/// Three faint arch outlines across a card, echoing salon doorways.
class _Arches extends CustomPainter {
  const _Arches();
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: .13);
    final w = s.width * .2;
    for (final x in [.24, .5, .76]) {
      final cx = s.width * x;
      final top = s.height * .38;
      final path = Path()
        ..moveTo(cx - w / 2, s.height + 2)
        ..lineTo(cx - w / 2, top + w / 2)
        ..arcToPoint(Offset(cx + w / 2, top + w / 2), radius: Radius.circular(w / 2))
        ..lineTo(cx + w / 2, s.height + 2);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

class _ReviewNudge extends StatelessWidget {
  final Appointment a;
  const _ReviewNudge(this.a);
  @override
  Widget build(BuildContext context) {
    final vm = context.read<HomeViewModel>();
    final s = vm.salon(a.salonId);
    final c = context.c;
    final name = s?.name ?? tr('the salon');
    void rate() => showReviewSheet(context, name, (stars, text, photos) => vm.addReview(a.id, stars, text, photos));
    return HCard(
      onTap: rate,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          artThumb(s?.palette ?? 0, photo: s?.cover, 48, radius: 24, name: s?.name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s == null ? tr('How was your visit?') : tr('How was {salon}?', {'salon': s.name}), maxLines: 2, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                const SizedBox(height: 2),
                Text(tr('Your review helps other customers choose.'), style: T.sm(context).copyWith(color: c.muted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Outlined pill: opens the stars straight away.
          Tap(
            onTap: rate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.brandText, width: 1.4),
              ),
              child: Text(tr('Rate'), style: T.ttl(context).copyWith(color: c.brandText, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}
