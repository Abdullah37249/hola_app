import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/ui.dart';
import '../../notifications/notifications.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';
import 'appointment_view.dart';
import 'walk_in_sheet.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../trade/viewmodels/trade_view_models.dart';
import '../../trade/views/new_order_page.dart';
import '../../trade/views/offers_page.dart';
import '../../trade/widgets/promo_card.dart';
import '../../trade/widgets/trade_widgets.dart';

/// Owner's dashboard: what needs an answer, who is next, today's numbers.
class SalonToday extends StatelessWidget {
  const SalonToday({super.key});
  @override
  Widget build(BuildContext context) => const SalonScope(child: _OwnerToday());
}

class _OwnerToday extends StatelessWidget {
  const _OwnerToday();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final s = vm.salon;
    if (s == null) return const SizedBox();
    final reqs = vm.requests();
    final next = vm.upNext();
    return BandView(
      role: 'salon',
      onRefresh: context.read<BookingRepository>().sync,
      children: [
        ...staggered([
          TopHead(eyebrow: '${s.name} · ${dLabel(today)}', title: '${greeting(now())}, ${vm.me?.firstName ?? ''}', oneLine: true, actions: const [NotificationBell()]),
          const SizedBox(height: 22),
        ]),
        // The day's numbers sit across the header's edge: half on the band, half on the page.
        BandMark(
          match: true, // every header ends at the same height (kTodayBand)
          child: Reveal(
            i: 1,
            child: KpiRow([Kpi(tr('Bookings today'), vm.countOn(today), hl: true), Kpi(tr('Expected today'), vm.revenueOn(today), format: (v) => rs(v)), Kpi(tr('Waiting for answer'), reqs.length)]),
          ),
        ),
        ...staggered([
          if (!s.isActive) ...[const SizedBox(height: 16), const VerificationBanner()],
          const SizedBox(height: 28),
        ], 2),
        if (reqs.isNotEmpty) ...[
          Reveal(
            i: 5,
            child: SecHead(tr('Needs your answer'), action: reqs.length > 3 ? tr('All {n}', {'n': reqs.length}) : null, onAction: () => pushPage(context, const _RequestsPage())),
          ),
          const SizedBox(height: 12),
          for (final (i, a) in reqs.take(3).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Reveal(
                i: 6 + i,
                child: ApptRow(
                  a: a,
                  showDay: true,
                  staffName: vm.firstNameOf(a.staffId),
                  onTap: () => pushPage(context, AppointmentDetailPage(id: a.id)),
                  actions: RequestActions(a),
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
        Reveal(
          i: 9,
          child: SecHead(tr('Up next today'), action: tr('Calendar'), onAction: () => context.read<SessionViewModel>().setTab('calendar')),
        ),
        const SizedBox(height: 12),
        if (next.isEmpty)
          Reveal(
            i: 10,
            child: HCard(
              child: EmptyState(
                icon: 'cal',
                title: tr('Nothing else booked today'),
                text: tr('New bookings from the HOLA app and walk-ins you add will show up here.'),
                cta: HButton(tr('Add a walk-in'), icon: 'plus', kind: BtnKind.secondary, small: true, onTap: () => showWalkInSheet(context, vm)),
              ),
            ),
          )
        else
          for (final (i, a) in next.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Reveal(
                i: 10 + i,
                child: ApptRow(
                  a: a,
                  staffName: vm.firstNameOf(a.staffId),
                  onTap: () => pushPage(context, AppointmentDetailPage(id: a.id)),
                ),
              ),
            ),
        const SizedBox(height: 28),
        Reveal(
          i: 14,
          child: _TodayProducts(salonId: s.id, canOrder: s.isActive),
        ),
      ],
    );
  }
}

class _RequestsPage extends StatelessWidget {
  const _RequestsPage();
  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        final reqs = vm.requests();
        return HPage(
          title: tr('Booking requests'),
          children: [
            const SizedBox(height: 8),
            if (reqs.isEmpty) EmptyState(icon: 'check', title: tr('All answered'), text: tr('New booking requests will appear here.')),
            for (final (i, a) in reqs.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Reveal(
                  i: i,
                  child: ApptRow(
                    a: a,
                    showDay: true,
                    staffName: vm.firstNameOf(a.staffId),
                    onTap: () => pushPage(context, AppointmentDetailPage(id: a.id)),
                    actions: RequestActions(a),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// HOLA professional products the salon can order, plus orders on the way.
class _TodayProducts extends StatelessWidget {
  final String salonId;
  final bool canOrder;
  const _TodayProducts({required this.salonId, required this.canOrder});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => SalonOrdersViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), salonId),
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonOrdersViewModel>();
        final c = context.c;
        final list = vm.featured;
        void shop() => canOrder ? pushPage(context, NewOrderPage(salonId: salonId)) : context.read<SessionViewModel>().setTab('products');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coupons HOLA sent this salon, shown as promotions.
            if (vm.offers.isNotEmpty) ...[
              SecHead(
                tr('Offers from HOLA'),
                action: tr('See all'),
                onAction: () => pushPage(context, OffersPage(salonId: salonId)),
              ),
              const SizedBox(height: 12),
              PromoCard(
                vm.offers.first,
                onUse: canOrder ? () => pushPage(context, NewOrderPage(salonId: salonId, coupon: vm.offers.first.code)) : null,
              ),
              if (vm.offers.length > 1) ...[
                const SizedBox(height: 8),
                Tap(
                  onTap: () => pushPage(context, OffersPage(salonId: salonId)),
                  child: Text(
                    tr('+{n} more offers', {'n': vm.offers.length - 1}),
                    style: T.sm(context).copyWith(color: c.brandText, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
            SecHead(tr('HOLA products'), action: list.isEmpty ? null : tr('See all'), onAction: () => context.read<SessionViewModel>().setTab('products')),
            const SizedBox(height: 12),
            if (vm.openCount > 0) ...[
              HCard(
                onTap: () => context.read<SessionViewModel>().setTab('products'),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    HIcon('box', size: 20, color: c.brandText),
                    const SizedBox(width: 12),
                    Expanded(child: Text(vm.openCount == 1 ? tr('1 order on the way') : tr('{n} orders on the way', {'n': vm.openCount}), style: T.ttl(context))),
                    HIcon('chev', size: 18, color: c.subtle),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (list.isEmpty)
              HCard(
                child: EmptyState(
                  icon: 'box',
                  title: tr('HOLA professional products'),
                  text: tr('Order colour, care and styling products for your salon at trade prices.'),
                  cta: HButton(tr('See products'), icon: 'box', kind: BtnKind.secondary, small: true, onTap: () => context.read<SessionViewModel>().setTab('products')),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in list)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _ProductMini(p, onTap: shop),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _ProductMini extends StatelessWidget {
  final Product p;
  final VoidCallback onTap;
  const _ProductMini(this.p, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final v = p.variants.isEmpty ? null : p.variants.first;
    return SizedBox(
      width: 148,
      child: HCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: ProductThumb(p, size: 84)),
            const SizedBox(height: 10),
            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.ttl(context).copyWith(fontSize: 14)),
            Text(tr(p.category), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context)),
            const SizedBox(height: 6),
            if (v != null) Text(rs(v.tradePrice), style: T.ttl(context).copyWith(color: context.c.brandText)),
            if (p.hasScheme) ...[const SizedBox(height: 6), SchemeBadge(p.schemeLabel)],
          ],
        ),
      ),
    );
  }
}
