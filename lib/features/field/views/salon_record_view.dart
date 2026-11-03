import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../trade/trade.dart';
import '../viewmodels/field_view_models.dart';
import '../widgets/field_widgets.dart';
import 'visit_view.dart';

/// Everything HOLA knows about one salon, plus verification and credit actions.
class SalonRecordPage extends StatelessWidget {
  final String id;
  const SalonRecordPage({super.key, required this.id});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => SalonRecordViewModel(id, salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), field: c.read<FieldRepository>(), trade: c.read<TradeRepository>()),
    child: const _Body(),
  );
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonRecordViewModel>();
    final s = vm.record;
    if (s == null) {
      return HPage(
        title: tr('Salon'),
        children: [EmptyState(icon: 'store', title: tr('Salon not found'), text: tr('It may have been removed.'))],
      );
    }
    final c = context.c;
    final owner = vm.owner(s.id);
    final rating = vm.rating;
    final services = vm.services;
    final active = services.where((x) => x.active).length;

    return HPage(
      title: s.name,
      hero: Reveal(
        child: SalonArt(s.palette, photo: s.cover, height: 150 + MediaQuery.paddingOf(context).top, radius: 0, name: s.name),
      ),
      children: staggered([
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: T.h1(context)),
                  Text(
                    [
                      vm.place(s.id),
                      tr('joined {date}', {'date': dLabel(s.createdAt)}),
                    ].where((x) => x.isNotEmpty).join(' · '),
                    style: T.sub(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(top: 6), child: StatusBadge(s.status)),
          ],
        ),
        const SizedBox(height: 16),
        _VerificationCard(vm: vm, salon: s, activeServices: active),
        const SizedBox(height: 24),
        SecHead(tr('Owner')),
        const SizedBox(height: 12),
        Group(
          children: [
            MRow(icon: 'user', title: owner?.name ?? tr('Unknown'), sub: owner?.email),
            if ((owner?.phone ?? '').isNotEmpty)
              MRow(
                icon: 'phone',
                tint: 2,
                title: owner!.phone,
                sub: tr('Call the owner'),
                onTap: () => launchUrl(Uri(scheme: 'tel', path: owner.phone.replaceAll(' ', ''))),
              ),
            if (s.phone.isNotEmpty && s.phone != owner?.phone)
              MRow(
                icon: 'store',
                tint: 1,
                title: s.phone,
                sub: tr('Salon phone'),
                onTap: () => launchUrl(Uri(scheme: 'tel', path: s.phone.replaceAll(' ', ''))),
              ),
          ],
        ),
        if (s.about.isNotEmpty) ...[const SizedBox(height: 12), Text(s.about, style: T.sm(context))],
        const SizedBox(height: 24),
        KpiStrip([
          Kpi(tr('Services live'), active, icon: 'scissors'),
          Kpi(tr('Team'), vm.team.length, icon: 'users'),
          Kpi(rating.count == 0 ? tr('No reviews yet') : plural(rating.count, 'review'), rating.average, format: (v) => rating.count == 0 ? '–' : v.toStringAsFixed(1), icon: 'star'),
        ]),
        const SizedBox(height: 24),
        SecHead(vm.branches.length == 1 ? tr('Location') : tr('{n} locations', {'n': vm.branches.length})),
        const SizedBox(height: 12),
        for (final b in vm.branches) Padding(padding: const EdgeInsets.only(bottom: 10), child: _BranchCard(b)),
        const SizedBox(height: 14),
        SecHead(tr('Menu'), action: services.isEmpty ? null : plural(services.length, 'service')),
        const SizedBox(height: 12),
        if (services.isEmpty)
          HCard(
            child: Text(tr('No services yet. Customers can\'t book until the owner adds a menu, and the salon can\'t be verified without one.'), style: T.sm(context).copyWith(color: c.muted)),
          )
        else
          CardList([
            for (final x in services.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            x.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.ttl(context).copyWith(color: x.active ? null : c.subtle),
                          ),
                          Text('${tr(x.category)} · ${fmtDur(x.durationMin)}${x.active ? '' : ' · ${tr('hidden')}'}', style: T.cap(context)),
                        ],
                      ),
                    ),
                    Text(
                      rs(x.price),
                      style: T.sm(context).copyWith(color: c.ink, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            if (services.length > 6)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(tr('+ {n} more', {'n': services.length - 6}), style: T.cap(context)),
              ),
          ]),
        const SizedBox(height: 24),
        SecHead(tr('Team')),
        const SizedBox(height: 12),
        CardList([
          for (final p in vm.team)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Avatar(vm.personName(p.accountId), size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(vm.personName(p.accountId), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                  ),
                  Text(p.title, style: T.cap(context)),
                ],
              ),
            ),
        ]),
        const SizedBox(height: 24),
        SecHead(tr('Trade credit'), action: tr('Set terms'), onAction: () => _termsSheet(context, vm, s)),
        const SizedBox(height: 12),
        CreditCard(salonId: s.id),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: HButton(
                tr('Statement'),
                icon: 'doc',
                kind: BtnKind.secondary,
                onTap: () => pushPage(context, StatementPage(salonId: s.id)),
              ),
            ),
            if (s.isActive) ...[
              const SizedBox(width: 10),
              Expanded(
                child: HButton(
                  tr('New order'),
                  icon: 'box',
                  onTap: () => pushPage(context, NewOrderPage(salonId: s.id)),
                ),
              ),
            ],
          ],
        ),
        if (!s.isActive)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('Product orders open once you verify the salon.'), style: T.cap(context)),
          ),
        const SizedBox(height: 24),
        SecHead(
          tr('Visits'),
          action: tr('Plan visit'),
          onAction: () => planVisitSheet(context, salonId: s.id),
        ),
        const SizedBox(height: 12),
        if (vm.visits.isEmpty)
          HCard(
            child: Text(tr('No visits yet.'), style: T.sm(context).copyWith(color: c.muted)),
          )
        else
          CardList([
            for (final v in vm.visits.take(6))
              VisitTile(
                visit: v,
                salon: tr(v.purpose),
                place: v.outcomes.isEmpty ? '' : [for (final o in v.outcomes) tr(visitOutcomes.firstWhere((x) => x.$1 == o, orElse: () => (o, o)).$2)].join(', '),
                showDate: true,
                onTap: () => pushPage(context, VisitPage(id: v.id)),
              ),
          ]),
        const SizedBox(height: 24),
        SecHead(tr('Recent orders')),
        const SizedBox(height: 12),
        if (vm.orders.isEmpty)
          HCard(
            child: Text(tr('No trade orders yet.'), style: T.sm(context).copyWith(color: c.muted)),
          )
        else
          VStack(gap: 10, [
            for (final o in vm.orders.take(5))
              OrderCard(
                order: o,
                onTap: () => pushPage(context, OrderDetailPage(id: o.id)),
              ),
          ]),
        const SizedBox(height: 32),
      ]),
    );
  }

  void _termsSheet(BuildContext context, SalonRecordViewModel vm, Salon s) {
    final limit = TextEditingController(text: s.creditLimit == 0 ? '' : '${s.creditLimit}');
    var days = s.creditDays;
    showHSheet<void>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) => VStack(gap: 14, [
          SheetHead(tr('Credit terms'), sub: tr('How much {salon} can order on credit, and how long they have to pay.', {'salon': s.name})),
          HField(label: tr('Credit limit (Rs)'), hint: tr('e.g. 100000'), controller: limit, keyboard: TextInputType.number, icon: 'cash'),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('Pay within'),
                  style: T.sm(ctx).copyWith(color: ctx.c.ink, fontWeight: FontWeight.w600),
                ),
              ),
              HStepper(value: days, min: 1, max: 120, onChanged: (v) => set(() => days = v)),
              const SizedBox(width: 8),
              Text(tr('days'), style: T.sm(ctx)),
            ],
          ),
          Text(tr('Set the limit to 0 to stop credit orders.'), style: T.cap(ctx)),
          HButton(
            tr('Save terms'),
            block: true,
            onTap: () async {
              final v = int.tryParse(limit.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              final ok = await attempt(() => vm.setTerms(v, days), success: tr('Credit terms saved'), icon: 'cash');
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ]),
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  final SalonRecordViewModel vm;
  final Salon salon;
  final int activeServices;
  const _VerificationCard({required this.vm, required this.salon, required this.activeServices});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = salon;
    Widget note(String title, String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: T.cap(context).copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(text, style: T.sm(context).copyWith(color: fg)),
        ],
      ),
    );

    Future<void> requestChanges() async {
      final t = await askText(
        context,
        title: tr('Request changes'),
        body: tr('Tell {salon} what to fix. They\'ll be notified and can resubmit.', {'salon': s.name}),
        label: tr('What needs to change?'),
        hint: tr('e.g. Add prices for all services'),
        confirm: tr('Send to owner'),
        minLength: 5,
      );
      if (t != null) await attempt(() => vm.requestChanges(t), success: tr('Owner notified'), icon: 'msg');
    }

    final checks = [(tr('Salon details and phone'), s.phone.isNotEmpty), (tr('At least one location'), vm.branches.isNotEmpty), (tr('Services on the menu'), activeServices > 0)];

    return switch (s.status) {
      SalonStatus.pending => HCard(
        child: VStack(gap: 12, [
          Text(tr('Verify this salon'), style: T.h3(context)),
          Text(tr('{salon} is already live for customers. Verifying adds the HOLA Verified badge and unlocks product orders.', {'salon': s.name}), style: T.sm(context)),
          for (final (label, ok) in checks)
            Row(
              children: [
                HIcon(ok ? 'check' : 'x', size: 18, color: ok ? c.ok : c.bad),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: T.sm(context).copyWith(color: c.ink)),
                ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: HButton(tr('Request changes'), kind: BtnKind.secondary, onTap: requestChanges),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HButton(
                  tr('Verify salon'),
                  icon: 'shield',
                  onTap: () => attempt(vm.approve, success: tr('{salon} is HOLA Verified', {'salon': s.name}), icon: 'shield', confetti: true),
                ),
              ),
            ],
          ),
        ]),
      ),
      SalonStatus.changes => HCard(
        child: VStack(gap: 12, [
          note(tr('Waiting for the owner'), s.statusNote ?? tr('Changes requested.'), c.accentSoft, c.accentInk),
          Row(
            children: [
              Expanded(
                child: HButton(tr('Edit request'), kind: BtnKind.secondary, onTap: requestChanges),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HButton(
                  tr('Verify now'),
                  icon: 'shield',
                  onTap: () => attempt(vm.approve, success: tr('{salon} is HOLA Verified', {'salon': s.name}), icon: 'shield'),
                ),
              ),
            ],
          ),
        ]),
      ),
      SalonStatus.suspended => HCard(
        child: VStack(gap: 12, [
          note(tr('Suspended'), s.statusNote ?? '', c.badSoft, c.badInk),
          HButton(
            tr('Reactivate salon'),
            icon: 'check',
            block: true,
            kind: BtnKind.ok,
            onTap: () async {
              if (await confirmSheet(context, title: tr('Reactivate {salon}?', {'salon': s.name}), body: tr('Customers will be able to find and book the salon again.'), confirm: tr('Reactivate'))) {
                await attempt(vm.reactivate, success: tr('{salon} reactivated', {'salon': s.name}));
              }
            },
          ),
        ]),
      ),
      _ => HCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.okSoft, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: HIcon('shield', size: 20, color: c.ok),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('HOLA Verified'), style: T.ttl(context)),
                  Text(tr('Badge shown to customers · product orders open'), style: T.cap(context)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            HButton(
              tr('Suspend'),
              small: true,
              kind: BtnKind.dangerSoft,
              onTap: () async {
                final t = await askText(
                  context,
                  title: tr('Suspend {salon}?', {'salon': s.name}),
                  body: tr('Customers won\'t be able to find or book the salon until you reactivate it.'),
                  label: tr('Reason'),
                  confirm: tr('Suspend salon'),
                  danger: true,
                  minLength: 5,
                );
                if (t != null) await attempt(() => vm.suspend(t), success: tr('{salon} suspended', {'salon': s.name}), icon: 'alert');
              },
            ),
          ],
        ),
      ),
    };
  }
}

class _BranchCard extends StatelessWidget {
  final Branch b;
  const _BranchCard(this.b);
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final todayIdx = today.weekday - 1;
    return HCard(
      child: VStack(gap: 10, [
        Row(
          children: [
            HIcon('pin', size: 20, color: c.brandText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name, style: T.ttl(context)),
                  Text([b.address, b.area, b.city].where((x) => x.isNotEmpty).join(', '), style: T.cap(context)),
                ],
              ),
            ),
          ],
        ),
        const HDivider(),
        for (var i = 0; i < 7; i++)
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  tr(weekdaysMon[i]),
                  style: T.cap(context).copyWith(color: i == todayIdx ? c.brandText : null, fontWeight: i == todayIdx ? FontWeight.w600 : null),
                ),
              ),
              Expanded(
                child: Text(
                  hoursText(b.hours[i]),
                  textAlign: TextAlign.right,
                  style: T.cap(context).copyWith(color: b.hours[i] == null ? c.subtle : c.ink),
                ),
              ),
            ],
          ),
      ]),
    );
  }
}
