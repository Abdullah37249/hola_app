import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
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

class _Today extends StatefulWidget {
  const _Today();
  @override
  State<_Today> createState() => _TodayState();
}

class _TodayState extends State<_Today> {
  String? _tab; // pick | way | done; first visit opens what needs doing

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DeliveriesViewModel>();
    final tab = _tab ?? (vm.outForDelivery.isNotEmpty ? 'way' : 'pick');
    final list = switch (tab) {
      'way' => vm.outForDelivery,
      'done' => vm.done,
      _ => vm.assigned,
    };
    return BandView(
      role: 'rider',
      onRefresh: vm.pull,
      children: [
        ...staggered([
          TopHead(
            eyebrow: '${tr('Deliveries')} · ${dLabel(today)}',
            title: tr('{greeting}, {name}', {
              'greeting': now().hour < 12
                  ? tr('Good morning')
                  : now().hour < 17
                  ? tr('Good afternoon')
                  : tr('Good evening'),
              'name': vm.firstName,
            }),
            sub: tr('Orders HOLA assigned to you'),
            actions: [NotificationBell()],
          ),
          const SizedBox(height: 18),
        ]),
        // The numbers sit across the header's edge.
        BandMark(
          child: Reveal(
            i: 1,
            child: KpiRow([
              Kpi(tr('To pick up'), vm.assigned.length, hl: true),
              Kpi(tr('On the way'), vm.outForDelivery.length),
              Kpi(tr('Cash to collect, Rs'), vm.cashToCollect, format: (v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${v.round()}'),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        ...staggered([
          Seg(
            opts: [
              ('pick', '${tr('To pick up')}${vm.assigned.isEmpty ? '' : ' · ${vm.assigned.length}'}'),
              ('way', '${tr('On the way')}${vm.outForDelivery.isEmpty ? '' : ' · ${vm.outForDelivery.length}'}'),
              ('done', tr('Done')),
            ],
            value: tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            HCard(
              child: switch (tab) {
                'way' => EmptyState(icon: 'truck', title: tr('Nothing on the way'), text: tr('Pick up an order from HOLA, then tap Picked up. It moves here with directions to the salon.')),
                'done' => EmptyState(icon: 'check', title: tr('No deliveries this week'), text: tr('Delivered orders from the last 7 days are listed here.')),
                _ =>
                  vm.isEmpty
                      ? EmptyState(icon: 'box', title: tr('No deliveries assigned yet'), text: tr('HOLA assigns trade orders to you. They will appear here, and you will get a notification.'))
                      : EmptyState(icon: 'check', title: tr('All picked up'), text: tr('No orders waiting at HOLA for you right now.')),
              },
            )
          else
            for (final o in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Builder(
                  builder: (context) {
                    final stop = vm.stop(o);
                    return DeliveryCard(
                      o: o,
                      stop: stop,
                      onTap: () => pushPage(context, DeliveryPage(id: o.id)),
                      onCall: stop.phone.isEmpty ? null : () => callPhone(stop.phone),
                      onPickUp: () async {
                        final ok = await attempt(() => vm.pickUp(o), success: tr('Picked up. Tap Start navigation to go'), icon: 'truck');
                        if (ok) setState(() => _tab = 'way');
                      },
                      onNavigate: () => navigateTo(stop),
                      collect: vm.collectFor(o),
                    );
                  },
                ),
              ),
        ], 2),
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
      onRefresh: vm.pull,
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
                Text(
                  hand.isEmpty ? tr('Nothing to hand over') : tr('From {deliveries}', {'deliveries': plural(hand.length, 'delivery', 'deliveries')}),
                  style: T.cap(context).merge(w.copyWith(color: Colors.white70)),
                ),
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
                for (final p in hand)
                  MRow(
                    icon: p.creditPayment ? 'doc' : 'box',
                    title: p.salonName.isNotEmpty ? p.salonName : (vm.salonFor(p.orderCode).isEmpty ? (p.creditPayment ? p.requestCode : p.orderCode) : vm.salonFor(p.orderCode)),
                    sub: [
                      if (p.creditPayment) tr('Credit payment {code}', {'code': p.requestCode}) else if (p.salonName.isNotEmpty || vm.salonFor(p.orderCode).isNotEmpty) p.orderCode,
                      if (p.receivedAt case final at?) '${dayLabel(at, today)} ${fmtTime(at)}',
                    ].join(' · '),
                    trailing: Text(
                      rs(p.amount),
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
