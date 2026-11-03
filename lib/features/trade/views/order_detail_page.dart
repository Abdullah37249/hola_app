import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/trade_view_models.dart';
import '../widgets/trade_widgets.dart';

/// One trade order: tracker, items, delivery proof and the actions the
/// signed-in role is allowed (salon owner or HOLA sales officer).
class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider(create: (c) => OrderDetailViewModel(c.read<TradeRepository>(), c.read<SalonRepository>(), c.read<AuthRepository>(), id), child: const _Body());
}

enum _St { done, cur, todo, bad }

class _Step {
  final String title, sub;
  final _St st;
  const _Step(this.title, this.sub, this.st);
}

class _Body extends StatelessWidget {
  const _Body();

  static const _labels = {
    OrderStatus.placed: 'Order placed',
    OrderStatus.approved: 'Approved by HOLA',
    OrderStatus.dispatched: 'Dispatched',
    OrderStatus.outForDelivery: 'Out for delivery',
    OrderStatus.delivered: 'Delivered',
    OrderStatus.confirmed: 'Receipt confirmed',
  };

  String _when(TradeOrder o, String s) {
    final t = o.at(s);
    return t == null ? '' : '${dLabel(t)}, ${fmtTime(t)}';
  }

  List<_Step> _steps(TradeOrder o, OrderDetailViewModel vm) {
    String sub(String s) {
      final w = _when(o, s);
      final extra = switch (s) {
        OrderStatus.dispatched || OrderStatus.outForDelivery => vm.rider == null ? '' : tr('Rider: {name}', {'name': vm.rider!.name}),
        OrderStatus.delivered => o.recipientName == null ? '' : tr('Received by {name}', {'name': o.recipientName}),
        _ => '',
      };
      return [w, extra].where((x) => x.isNotEmpty).join(' · ');
    }

    final flow = OrderStatus.flow;
    switch (o.status) {
      case OrderStatus.underReview:
        return [
          _Step(tr(_labels[OrderStatus.placed]!), sub(OrderStatus.placed), _St.done),
          _Step(tr('Credit review'), tr('Over the available credit. HOLA is reviewing it.'), _St.cur),
          for (final s in flow.skip(1)) _Step(tr(_labels[s]!), '', _St.todo),
        ];
      case OrderStatus.failed:
        return [
          for (final s in flow.take(3)) _Step(tr(_labels[s]!), sub(s), _St.done),
          _Step(tr('Delivery failed'), [_when(o, OrderStatus.failed), tr(o.failReason ?? '')].where((x) => x.isNotEmpty).join(' · '), _St.bad),
          for (final s in flow.skip(4)) _Step(tr(_labels[s]!), '', _St.todo),
        ];
      case OrderStatus.cancelled:
        final reached = [
          for (final s in flow)
            if (o.at(s) != null) s,
        ];
        final note = o.history.lastWhere((h) => h.status == OrderStatus.cancelled).note ?? '';
        return [
          for (final s in reached) _Step(tr(_labels[s]!), sub(s), _St.done),
          _Step(tr('Cancelled'), [_when(o, OrderStatus.cancelled), note].where((x) => x.isNotEmpty).join(' · '), _St.bad),
        ];
      default:
        final i = flow.indexOf(o.status);
        return [
          for (var k = 0; k < flow.length; k++)
            _Step(
              tr(_labels[flow[k]]!),
              k <= i ? sub(flow[k]) : '',
              k < i || (k == i && (flow[k] == OrderStatus.confirmed || flow[k] == OrderStatus.placed))
                  ? _St.done
                  : k == i
                  ? _St.cur
                  : _St.todo,
            ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OrderDetailViewModel>();
    final o = vm.order;
    final c = context.c;
    if (o == null) {
      return HPage(
        title: tr('Order'),
        children: [EmptyState(icon: 'box', title: tr('Order not found'), text: tr('It may have been removed.'))],
      );
    }
    final steps = _steps(o, vm);
    final freeUnits = o.lines.fold(0, (s, l) => s + l.freeQty);
    final actions = _actions(context, vm, o);
    return HPage(
      title: tr('Order {code}', {'code': o.code}),
      footer: actions.isEmpty ? null : VStack(gap: 8, actions),
      children: staggered([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.code, style: T.h1(context)),
                  Text('${vm.salon?.name ?? tr('Salon')}${vm.branch == null ? '' : ' · ${vm.branch!.area}'}', style: T.sub(context)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(top: 6), child: StatusBadge(o.status)),
          ],
        ),
        const SizedBox(height: 16),
        HCard(
          child: Column(children: [for (final (i, s) in steps.indexed) _StepRow(s, last: i == steps.length - 1)]),
        ),
        if (vm.isOfficer && o.status == OrderStatus.underReview && vm.credit != null) ...[
          const SizedBox(height: 16),
          _ReviewNote(order: o, credit: vm.credit!),
          const SizedBox(height: 12),
          CreditCard(salonId: o.salonId),
        ],
        const SizedBox(height: 24),
        SecHead(tr('Items')),
        const SizedBox(height: 12),
        HCard(
          child: VStack(gap: 12, [
            for (final l in o.lines)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (vm.product(l.productId) case final p?) ...[ProductThumb(p, size: 40), const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.name, style: T.ttl(context)),
                        Text('${l.qty} × ${rs(l.unitPrice)}', style: T.sub(context)),
                        if (l.freeQty > 0) Padding(padding: const EdgeInsets.only(top: 4), child: SchemeBadge(tr('+{n} free', {'n': l.freeQty}))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(rs(l.total), style: T.ttl(context)),
                ],
              ),
            const HDivider(),
            KV(tr('Units'), '${plural(o.units, 'unit')}${freeUnits > 0 ? tr(' (incl. {n} free)', {'n': freeUnits}) : ''}'),
            KV(tr('Payment'), o.isCod ? tr('Cash on delivery') : tr('HOLA credit')),
            if (vm.placedBy != null) KV(tr('Placed by'), vm.placedBy!.name),
            if (o.discount != 0) ...[
              KV(tr('Subtotal'), rs(o.subtotal)),
              KV(tr('Coupon {code}', {'code': o.couponCode ?? ''}), '− ${rs(o.discount)}', vColor: context.c.ok),
            ],
            const HDivider(),
            Row(
              children: [
                Expanded(child: Text(tr('Total'), style: T.h3(context))),
                Text(rs(o.total), style: T.h1(context).copyWith(fontSize: 26)),
              ],
            ),
          ]),
        ),
        if (o.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          HCard(
            color: c.surface2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HIcon('doc', size: 20, color: c.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(o.notes, style: T.sm(context))),
              ],
            ),
          ),
        ],
        if (o.signature != null) ...[
          const SizedBox(height: 24),
          SecHead(tr('Proof of delivery')),
          const SizedBox(height: 12),
          HCard(
            child: VStack(gap: 10, [
              KV(tr('Received by'), o.recipientName ?? ''),
              if (o.at(OrderStatus.delivered) case final t?) KV(tr('Delivered'), '${dLabel(t)}, ${fmtTime(t)}'),
              if (o.isCod && o.cashCollected != null) KV(tr('Cash collected'), rs(o.cashCollected!)),
              if (vm.rider != null) KV(tr('Rider'), vm.rider!.name),
              if (o.deliveredWhere case final w?) KV(tr('Location'), w.label),
              SignatureView(o.signature!),
            ]),
          ),
        ],
        // The footer is taller than HPage's default room when it stacks several actions.
        SizedBox(height: 16 + 56.0 * (actions.length > 1 ? actions.length - 1 : 0)),
      ]),
    );
  }

  List<Widget> _actions(BuildContext context, OrderDetailViewModel vm, TradeOrder o) {
    final buttons = <Widget>[
      if (vm.canConfirmReceipt)
        HButton(
          tr('Confirm I received everything'),
          icon: 'check',
          kind: BtnKind.ok,
          block: true,
          onTap: () => attempt(vm.confirmReceipt, success: tr('Receipt confirmed'), confetti: true),
        ),
      if (vm.canApprove) HButton(o.status == OrderStatus.underReview ? tr('Approve over limit') : tr('Approve order'), icon: 'check', block: true, onTap: () => _approve(context, vm, o)),
      if (vm.canDispatch) HButton(o.status == OrderStatus.failed ? tr('Re-dispatch to a rider') : tr('Dispatch to a rider'), icon: 'truck', block: true, onTap: () => _dispatch(context, vm)),
      if (vm.canOwnerCancel || vm.canOfficerCancel) HButton(tr('Cancel order'), kind: BtnKind.ghost, block: true, small: true, onTap: () => _cancel(context, vm)),
    ];
    return buttons;
  }

  Future<void> _approve(BuildContext context, OrderDetailViewModel vm, TradeOrder o) async {
    if (o.status == OrderStatus.underReview) {
      final ok = await confirmSheet(
        context,
        title: tr('Approve over the credit limit?'),
        body: tr('The salon will owe {owed} after this order on a {limit} limit.', {'owed': rs(vm.credit!.outstanding), 'limit': rs(vm.credit!.limit)}),
        confirm: tr('Approve anyway'),
      );
      if (!ok) return;
    }
    await attempt(vm.approve, success: tr('Order approved'));
  }

  Future<void> _cancel(BuildContext context, OrderDetailViewModel vm) async {
    final reason = await askText(
      context,
      title: tr('Cancel this order?'),
      body: vm.order!.isCod ? tr('Reserved stock is released.') : tr('Reserved stock is released and the credit is returned.'),
      label: tr('Reason'),
      hint: vm.isOwner ? tr('e.g. Ordered by mistake') : tr('e.g. Salon asked to cancel'),
      confirm: tr('Cancel order'),
      danger: true,
      minLength: vm.isOfficer ? 3 : 0,
    );
    if (reason == null) return;
    await attempt(() => vm.cancel(reason), success: tr('Order cancelled'), icon: 'x');
  }

  Future<void> _dispatch(BuildContext context, OrderDetailViewModel vm) async {
    final riders = vm.riders;
    final picked = await showHSheet<String>(
      context,
      (ctx) => VStack(gap: 14, [
        SheetHead(tr('Choose a rider'), sub: tr('They get the delivery straight away.')),
        if (riders.isEmpty)
          EmptyState(icon: 'truck', title: tr('No riders yet'), text: tr('Delivery riders appear here once they sign up for HOLA as a rider.'))
        else
          Group(
            children: [
              for (final r in riders)
                MRow(
                  icon: 'truck',
                  title: r.name,
                  sub: [r.phone, if (r.city.isNotEmpty) r.city].join(' · '),
                  trailing: HIcon('chev', size: 18, color: ctx.c.subtle),
                  onTap: () => Navigator.pop(ctx, r.id),
                ),
            ],
          ),
      ]),
    );
    if (picked == null) return;
    await attempt(() => vm.dispatch(picked), success: tr('Dispatched'), icon: 'truck');
  }
}

class _ReviewNote extends StatelessWidget {
  const _ReviewNote({required this.order, required this.credit});
  final TradeOrder order;
  final CreditSummary credit;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // The order's own charge is already counted in outstanding.
    final over = credit.outstanding - credit.limit;
    return HCard(
      color: c.accentSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HIcon('alert', size: 20, color: c.accentInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              over > 0
                  ? tr('With this order the salon is {over} over its {limit} limit.', {'over': rs(over), 'limit': rs(credit.limit)})
                  : tr('This order went to review when credit was short. It now fits the limit.'),
              style: T.sm(context).copyWith(color: c.accentInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow(this.s, {required this.last});
  final _Step s;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final done = s.st == _St.done, cur = s.st == _St.cur, bad = s.st == _St.bad;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: bad ? G.danger : null,
                  color: bad
                      ? null
                      : done
                      ? c.brand
                      : cur
                      ? c.surface
                      : c.bg2,
                  // Pending steps need an outline in dark mode, where bg2 is close to the card.
                  border: cur
                      ? Border.all(color: c.brand, width: 2)
                      : done || bad || !c.dark
                      ? null
                      : Border.all(color: c.subtle, width: 1.5),
                ),
                alignment: Alignment.center,
                child: done || bad
                    ? HIcon(bad ? 'x' : 'check', size: 14, stroke: 3, color: Colors.white)
                    : cur
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
                      )
                    : null,
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: done
                        ? c.brand
                        : c.dark
                        ? c.subtle.withValues(alpha: .6)
                        : c.line,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    style: T
                        .ttl(context)
                        .copyWith(
                          color: s.st == _St.todo
                              ? c.subtle
                              : bad
                              ? c.badInk
                              : c.ink,
                        ),
                  ),
                  if (s.sub.isNotEmpty) Text(s.sub, style: T.cap(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens an order from anywhere in the trade feature.
void openOrder(BuildContext context, String id) => pushPage(context, OrderDetailPage(id: id));
