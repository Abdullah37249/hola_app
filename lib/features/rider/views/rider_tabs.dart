import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../notifications/notifications.dart';
import '../../profile/profile.dart';
import '../viewmodels/cash_view_model.dart';
import '../viewmodels/deliveries_view_model.dart';
import '../widgets/delivery_card.dart';
import 'delivery_view.dart';

/// Deliveries tab: what to deliver now, next, what failed and what's done.
class RiderToday extends StatelessWidget {
  const RiderToday({super.key});
  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider(create: (c) => DeliveriesViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), c.read<AuthRepository>()), child: const _Today());
}

class _Today extends StatelessWidget {
  const _Today();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DeliveriesViewModel>();
    Widget section(String title, List<TradeOrder> xs) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        SecHead(title),
        const SizedBox(height: 12),
        VStack(gap: 12, [
          for (final o in xs)
            DeliveryCard(
              o: o,
              stop: vm.stop(o),
              onTap: () => pushPage(context, DeliveryPage(id: o.id)),
            ),
        ]),
      ],
    );
    return BandView(
      role: 'rider',
      children: [
        ...staggered([
          TopHead(eyebrow: dLabel(today), title: tr('Deliveries'), actions: [NotificationBell()]),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Kpi(tr('To deliver'), vm.toDeliver, hl: true)),
              const SizedBox(width: 10),
              Expanded(child: Kpi(tr('Delivered today'), vm.deliveredToday)),
              const SizedBox(width: 10),
              Expanded(child: Kpi(tr('Cash to collect, Rs'), vm.cashToCollect, format: (v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${v.round()}')),
            ],
          ),
        ]),
        const BandMark(),
        if (vm.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: HCard(
              child: EmptyState(icon: 'truck', title: tr('No deliveries assigned yet'), text: tr('HOLA assigns trade orders to you. They will appear here, and you will get a notification.')),
            ),
          )
        else ...[
          // Nothing to do now: say so first, then show the history.
          if (vm.toDeliver == 0)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: HCard(
                child: EmptyState(icon: 'check', title: tr('All caught up'), text: tr('Nothing left to deliver right now. New orders appear here with a notification.')),
              ),
            ),
          if (vm.outForDelivery.isNotEmpty) Reveal(i: 3, child: section(tr('On the way'), vm.outForDelivery)),
          if (vm.assigned.isNotEmpty) Reveal(i: 4, child: section(tr('Up next'), vm.assigned)),
          if (vm.failed.isNotEmpty) Reveal(i: 5, child: section(tr("Couldn't deliver"), vm.failed)),
          if (vm.delivered.isNotEmpty) Reveal(i: 6, child: section(tr('Delivered this week'), vm.delivered)),
        ],
      ],
    );
  }
}

/// Cash tab: COD money in hand and handovers to HOLA.
class RiderCash extends StatelessWidget {
  const RiderCash({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => CashViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), c.read<AuthRepository>()), child: const _Cash());
}

class _Cash extends StatelessWidget {
  const _Cash();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CashViewModel>();
    final c = context.c;
    final hand = vm.inHand, hist = vm.history;
    const w = TextStyle(color: Colors.white);
    return BandView(
      role: 'rider',
      children: [
        ...staggered([
          TopHead(title: tr('Cash'), sub: tr('Cash on delivery money you are carrying')),
          const SizedBox(height: 16),
          HCard(
            gradient: G.credit,
            radius: 22,
            padding: const EdgeInsets.all(20),
            shadow: const [BoxShadow(color: Color(0xB300285A), blurRadius: 36, spreadRadius: -14, offset: Offset(0, 18))],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const HIcon('cash', size: 18, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text(tr('In hand'), style: T.cap(context).merge(w.copyWith(color: Colors.white70))),
                  ],
                ),
                const SizedBox(height: 4),
                CountUp(vm.total, format: rs, style: T.display(context).merge(w)),
                Text(hand.isEmpty ? tr('Nothing to hand over') : tr('From {deliveries}', {'deliveries': plural(hand.length, 'delivery', 'deliveries')}), style: T.cap(context).merge(w.copyWith(color: Colors.white70))),
              ],
            ),
          ),
        ]),
        const BandMark(),
        ...staggered([
          const SizedBox(height: 14),
          if (hand.isNotEmpty) ...[
            Group(
              children: [
                for (final o in hand)
                  MRow(
                    icon: 'box',
                    title: vm.salonName(o.salonId),
                    sub: '${o.code} · ${o.recipientName ?? ''}',
                    trailing: Text(
                      rs(o.cashCollected ?? 0),
                      style: T.sm(context).copyWith(color: c.ink, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            HButton(
              tr('Hand over {amount} to HOLA', {'amount': rs(vm.total)}),
              icon: 'hand',
              block: true,
              onTap: () async {
                final ok = await confirmSheet(
                  context,
                  title: tr('Hand over {amount}?', {'amount': rs(vm.total)}),
                  body: tr('Give the cash to the HOLA warehouse. A sales officer will confirm they received it.'),
                  confirm: tr('Record handover'),
                );
                if (ok) await attempt(vm.handOver, success: tr('Handover recorded. Waiting for HOLA to confirm'));
              },
            ),
          ],
          const SizedBox(height: 24),
          SecHead(tr('Handovers')),
          const SizedBox(height: 12),
          if (hist.isEmpty)
            HCard(
              child: EmptyState(icon: 'cash', title: tr('No handovers yet'), text: tr('When you hand cash to HOLA it is listed here, with who confirmed it and when.')),
            )
          else
            Group(
              children: [
                for (final h in hist)
                  MRow(
                    icon: h.status == 'CONFIRMED' ? 'check' : 'clock',
                    tint: h.status == 'CONFIRMED' ? 3 : 1,
                    title: rs(h.amount),
                    sub: h.status == 'CONFIRMED'
                        ? tr('Confirmed by {name} · {day} {time}', {'name': vm.confirmedBy(h) ?? 'HOLA', 'day': dayLabel(h.confirmedAt!, today), 'time': fmtTime(h.confirmedAt!)})
                        : tr('Handed over {day} {time} · {deliveries}', {'day': dayLabel(h.at, today), 'time': fmtTime(h.at), 'deliveries': plural(h.orderIds.length, 'delivery', 'deliveries')}),
                    trailing: ToneBadge(h.status == 'CONFIRMED' ? tr('Confirmed') : tr('Pending'), tone: h.status == 'CONFIRMED' ? 'ok' : 'warn'),
                  ),
              ],
            ),
        ], 3),
      ],
    );
  }
}

/// More tab: account and app settings.
class RiderMore extends StatelessWidget {
  const RiderMore({super.key});
  @override
  Widget build(BuildContext context) => BandView(
    role: 'rider',
    children: [
      ...staggered([TopHead(title: tr('More')), const SizedBox(height: 16), AccountCard()]),
      const BandMark(),
      ...staggered([const SizedBox(height: 24), AppSettingsGroup(), const SizedBox(height: 24), SignOutButton()], 3),
    ],
  );
}
