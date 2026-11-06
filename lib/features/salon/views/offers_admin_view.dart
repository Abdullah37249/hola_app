import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../customer/widgets/offer_card.dart' show offText, dayMonth, offerGradient;
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';

/// The salon's offers on its services: running, upcoming, switched off and ended.
class SalonOffersPage extends StatelessWidget {
  const SalonOffersPage({super.key});
  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        final t = now();
        // Running and upcoming first, then switched off, then ended.
        int rank(ServiceOffer o) => switch (o.statusAt(t)) {
          'ACTIVE' => 0,
          'SCHEDULED' => 1,
          'INACTIVE' => 2,
          _ => 3,
        };
        final xs = [...vm.offers]..sort((a, b) => rank(a).compareTo(rank(b)));
        final canAdd = vm.activeServices.isNotEmpty;
        return HPage(
          title: tr('Offers & discounts'),
          footer: FootBar(
            child: HButton(tr('New offer'), icon: 'plus', block: true, onTap: canAdd ? () => showOfferSheet(context, vm) : null),
          ),
          children: [
            const SizedBox(height: 8),
            if (xs.isEmpty)
              HCard(
                child: EmptyState(
                  icon: 'sparkle',
                  title: tr('No offers yet'),
                  text: canAdd ? tr('Put a discount on any service, e.g. 20% off a haircut this week. Clients see it while it runs.') : tr('Add services to your menu first, then put offers on them.'),
                ),
              ),
            for (final (i, o) in xs.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Reveal(
                  i: i,
                  child: _OfferRow(o, vm: vm),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _OfferRow extends StatelessWidget {
  const _OfferRow(this.o, {required this.vm});
  final ServiceOffer o;
  final SalonViewModel vm;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final svc = vm.salons.service(o.serviceId);
    final price = svc?.price ?? o.servicePrice;
    final status = o.statusAt(now());
    final stats = vm.offerStats(o);
    final ended = status == 'EXPIRED';
    final (label, tone) = switch (status) {
      'ACTIVE' => (tr('Running'), 'ok'),
      'SCHEDULED' => (tr('Starts {date}', {'date': dayMonth(o.startsAt)}), 'info'),
      'INACTIVE' => (tr('Off'), 'mute'),
      _ => (tr('Ended'), 'mute'),
    };
    return HCard(
      onTap: () => showOfferSheet(context, vm, existing: o),
      child: Opacity(
        opacity: status == 'ACTIVE' || status == 'SCHEDULED' ? 1 : .6,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: offerGradient, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Text('%', style: T.h2(context).copyWith(color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${offText(o)} · ${svc?.name ?? o.serviceName}', maxLines: 2, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                  Text('${rs(price)} → ${rs(price - o.discountOn(price))}', style: T.sm(context).copyWith(color: c.ink)),
                  Text(
                    [
                      '${dayMonth(o.startsAt)} – ${dayMonth(o.lastDay)}',
                      if (stats.used > 0) tr('{n} used', {'n': stats.used}),
                      if (stats.held > 0) tr('{n} on open bookings', {'n': stats.held}),
                    ].join(' · '),
                    style: T.cap(context),
                  ),
                  const SizedBox(height: 6),
                  ToneBadge(label, tone: tone, live: status == 'ACTIVE'),
                ],
              ),
            ),
            if (!ended) ...[
              const SizedBox(width: 8),
              HSwitch(
                on: o.active,
                onChanged: (v) => attempt(() => vm.setOfferActive(o.id, v), success: v ? tr('Offer switched on') : tr('Offer switched off'), icon: v ? 'check' : 'x'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Create or edit an offer.
Future<void> showOfferSheet(BuildContext context, SalonViewModel vm, {ServiceOffer? existing}) => showHSheet(context, (ctx) => _OfferForm(vm: vm, o: existing));

class _OfferForm extends StatefulWidget {
  const _OfferForm({required this.vm, this.o});
  final SalonViewModel vm;
  final ServiceOffer? o;
  @override
  State<_OfferForm> createState() => _OfferFormState();
}

class _OfferFormState extends State<_OfferForm> {
  late String? serviceId = widget.o?.serviceId ?? (widget.vm.activeServices.length == 1 ? widget.vm.activeServices.first.id : null);
  late String type = widget.o?.discountType ?? DiscountType.percent;
  late final value = TextEditingController(text: widget.o == null ? '' : '${widget.o!.discountValue}');
  late DateTime from = widget.o?.startsAt ?? today;
  late DateTime to = widget.o?.lastDay ?? addDays(today, 6);
  late bool active = widget.o?.active ?? true;
  final errors = FieldErrors();

  @override
  void dispose() {
    value.dispose();
    errors.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(value.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  Future<DateTime?> _pick(DateTime initial, DateTime first) {
    final start = first.isAfter(initial) ? first : initial;
    return showDatePicker(context: context, initialDate: start, firstDate: first, lastDate: addDays(today, 365));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final vm = widget.vm;
    final editing = widget.o != null;
    // An offer may already be on a service that is now hidden: keep it pickable.
    final svcs = [...vm.activeServices, if (widget.o != null && !vm.activeServices.any((s) => s.id == widget.o!.serviceId)) ?vm.salons.service(widget.o!.serviceId)];
    final svc = serviceId == null ? null : vm.salons.service(serviceId!);
    // Preview only a discount the save would accept (1–90%, or under the price).
    final valid = type == DiscountType.percent ? _value >= 1 && _value <= 90 : svc != null && _value >= 1 && _value <= maxOfferAmount(svc.price);
    final off = svc == null || !valid
        ? null
        : type == DiscountType.percent
        ? (svc.price * _value / 100).round().clamp(0, svc.price)
        : _value.clamp(0, svc.price);
    Widget dateBox(String label, DateTime d, VoidCallback onTap) => Expanded(
      child: Tap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: T.cap(context)),
              Text(dLabel(d), style: T.ttl(context)),
            ],
          ),
        ),
      ),
    );
    return VStack(gap: 14, [
      SheetHead(editing ? tr('Edit offer') : tr('New offer'), sub: editing ? null : tr('Clients see the discount on this service while the offer runs. Each client can use it once.')),
      Text(tr('Service'), style: HField.labelStyle(context)),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final s in svcs) HChip(s.name, on: serviceId == s.id, onTap: () => setState(() => serviceId = s.id))],
      ),
      Text(tr('Discount'), style: HField.labelStyle(context)),
      Seg(opts: [(DiscountType.percent, tr('Percent')), (DiscountType.amount, tr('Amount (Rs)'))], value: type, onChanged: (v) => setState(() => type = v)),
      HField(
        label: type == DiscountType.percent ? tr('Percent off') : tr('Rupees off'),
        hint: type == DiscountType.percent ? tr('e.g. 20') : tr('e.g. 500'),
        controller: value,
        keyboard: TextInputType.number,
        action: TextInputAction.done,
        name: 'value',
        errors: errors,
        onChanged: (_) => setState(() {}),
      ),
      if (svc != null && off != null)
        Text(
          tr('{service}: {before} → {after} for clients', {'service': svc.name, 'before': rs(svc.price), 'after': rs(svc.price - off)}),
          style: T.sm(context).copyWith(color: c.ok, fontWeight: FontWeight.w600),
        ),
      Row(
        children: [
          dateBox(tr('First day'), from, () async {
            final d = await _pick(from, today);
            if (d == null) return;
            setState(() {
              from = d;
              if (to.isBefore(d)) to = d;
            });
          }),
          const SizedBox(width: 10),
          dateBox(tr('Last day'), to, () async {
            final d = await _pick(to, from.isAfter(today) ? from : today);
            if (d != null) setState(() => to = d);
          }),
        ],
      ),
      Group(
        children: [
          SettingRow(
            title: tr('Offer is on'),
            sub: tr('Switch off to pause it without deleting'),
            control: HSwitch(on: active, onChanged: (v) => setState(() => active = v)),
          ),
        ],
      ),
      HButton(
        editing ? tr('Save changes') : tr('Create offer'),
        block: true,
        onTap: serviceId == null
            ? null
            : () async {
                final ok = await attempt(
                  () => vm.saveOffer(id: widget.o?.id, serviceId: serviceId!, discountType: type, discountValue: _value, startDay: from, lastDay: to, active: active),
                  success: editing ? tr('Saved') : tr('Offer created'),
                  errors: errors,
                );
                if (ok && context.mounted) Navigator.pop(context);
              },
      ),
      if (editing)
        HButton(
          tr('Delete offer'),
          kind: BtnKind.ghost,
          block: true,
          onTap: () async {
            if (!await confirmSheet(
              context,
              title: tr('Delete this offer?'),
              body: tr('Clients stop seeing it. Bookings already made with it keep their discounted price.'),
              confirm: tr('Delete'),
              danger: true,
            )) {
              return;
            }
            final ok = await attempt(() => vm.deleteOffer(widget.o!.id), success: tr('Offer deleted'), icon: 'x');
            if (ok && context.mounted) Navigator.pop(context);
          },
        ),
    ]);
  }
}
