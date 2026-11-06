import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../chat/chat.dart';
import '../viewmodels/returns_view_models.dart';
import 'order_detail_page.dart';

// ─── the salon's returns ─────────────────────────────────────────────────────

/// Every return request of the salon (HOLA's team: of every salon).
class ReturnsPage extends StatelessWidget {
  const ReturnsPage({super.key, this.salonId});
  final String? salonId;
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => ReturnsViewModel(c.read<ReturnRepository>(), salonId: salonId),
    child: const _ReturnsBody(),
  );
}

class _ReturnsBody extends StatefulWidget {
  const _ReturnsBody();
  @override
  State<_ReturnsBody> createState() => _ReturnsBodyState();
}

class _ReturnsBodyState extends State<_ReturnsBody> {
  String tab = 'open';
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReturnsViewModel>();
    final xs = tab == 'open' ? vm.open : vm.closed;
    return HPage(
      title: tr('Returns & refunds'),
      onRefresh: vm.reload,
      children: [
        ...staggered([
          Text(tr('Returns & refunds'), style: T.h1(context)),
          Text(tr('Return products from a delivered order: get them replaced or the money back.'), style: T.sub(context)),
          const SizedBox(height: 16),
          Seg(
            opts: [
              ('open', tr('Open ({n})', {'n': vm.open.length})),
              ('closed', tr('Finished ({n})', {'n': vm.closed.length})),
            ],
            value: tab,
            onChanged: (v) => setState(() => tab = v),
          ),
          const SizedBox(height: 14),
        ]),
        if (xs.isEmpty)
          HCard(
            child: EmptyState(
              icon: 'box',
              title: tab == 'open' ? tr('No open returns') : tr('Nothing finished yet'),
              text: tr('To return something, open a delivered order and tap "Return products".'),
            ),
          ),
        for (final (i, r) in xs.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Reveal(i: i, child: ReturnCard(r)),
          ),
      ],
    );
  }
}

/// One return in a list.
class ReturnCard extends StatelessWidget {
  const ReturnCard(this.r, {super.key});
  final ReturnRequest r;
  @override
  Widget build(BuildContext context) {
    final (label, tone) = returnStatusLabel(r.status);
    return HCard(
      onTap: () => pushPage(context, ReturnDetailPage(id: r.id)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: context.c.brandSoft, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: HIcon(r.option == ReturnOption.replace ? 'again' : 'cash', size: 22, color: context.c.brandText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.code} · ${tr('Order {code}', {'code': r.orderCode})}', style: T.ttl(context)),
                Text([returnOptionLabel(r.option, cod: r.cod), plural(r.units, 'unit'), rs(r.approvedAmount ?? r.amount)].join(' · '), style: T.sm(context)),
                const SizedBox(height: 6),
                ToneBadge(label, tone: tone, live: r.status == ReturnStatus.awaitingSalon),
              ],
            ),
          ),
          HIcon('chev', size: 18, color: context.c.subtle),
        ],
      ),
    );
  }
}

// ─── a new return ────────────────────────────────────────────────────────────

/// Picks what goes back, why, and what the salon wants instead.
class NewReturnPage extends StatelessWidget {
  const NewReturnPage({super.key, required this.orderId});
  final String orderId;
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => NewReturnViewModel(c.read<ReturnRepository>(), c.read<TradeRepository>(), orderId), child: const _NewReturn());
}

class _NewReturn extends StatefulWidget {
  const _NewReturn();
  @override
  State<_NewReturn> createState() => _NewReturnState();
}

class _NewReturnState extends State<_NewReturn> {
  final note = TextEditingController();
  final errors = FieldErrors();

  @override
  void dispose() {
    note.dispose();
    errors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NewReturnViewModel>();
    final o = vm.order;
    final c = context.c;
    if (o == null) {
      return HPage(
        title: tr('Return products'),
        children: [EmptyState(icon: 'box', title: tr('Order not found'), text: tr('It may have been removed.'))],
      );
    }
    final lines = o.lines.where((l) => vm.left(l) > 0 || vm.qtyOf(l.variantId) > 0).toList();
    final explain = vm.option == ReturnOption.replace
        ? tr('A rider collects these products and HOLA sends new ones, free of charge.')
        : o.isCod
        ? tr('You paid in cash: HOLA offers a voucher or a replacement, and you accept or decline. There is no cash back.')
        : tr('You paid on HOLA credit: once HOLA approves and a rider collects the products, their value comes off your outstanding balance.');
    return HPage(
      title: tr('Return products'),
      footer: FootBar(
        child: HButton(
          vm.units == 0 ? tr('Pick products to return') : tr('Send to HOLA · {amount}', {'amount': rs(vm.value)}),
          icon: 'check',
          block: true,
          onTap: vm.units == 0 || vm.reason == null
              ? null
              : () async {
                  ReturnRequest? r;
                  final ok = await attempt(() async => r = await vm.submit(note.text), success: tr('Return request sent to HOLA'), errors: errors);
                  if (ok && r != null && context.mounted) Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ReturnDetailPage(id: r!.id)));
                },
        ),
      ),
      children: staggered([
        Text(tr('Return products'), style: T.h1(context)),
        Text(tr('Order {code} · {payment}', {'code': o.code, 'payment': o.isCod ? tr('Cash on delivery') : tr('HOLA credit')}), style: T.sub(context)),
        const SizedBox(height: 20),
        SecHead(tr('What goes back')),
        const SizedBox(height: 10),
        HCard(
          child: lines.isEmpty
              ? Text(tr('Everything on this order is already in a return.'), style: T.sm(context))
              : VStack(gap: 14, [
                  for (final l in lines)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.name, style: T.ttl(context)),
                              Text(tr('{n} can be returned', {'n': vm.left(l)}), style: T.cap(context)),
                            ],
                          ),
                        ),
                        HStepper(value: vm.qtyOf(l.variantId), max: vm.left(l), onChanged: (n) => vm.setQty(l, n)),
                      ],
                    ),
                ]),
        ),
        const SizedBox(height: 20),
        SecHead(tr('What do you want?')),
        const SizedBox(height: 10),
        Seg(
          opts: [
            (ReturnOption.replace, tr('Replace product')),
            (ReturnOption.refund, returnOptionLabel(ReturnOption.refund, cod: o.isCod)),
          ],
          value: vm.option,
          onChanged: vm.setOption,
        ),
        const SizedBox(height: 8),
        Text(explain, style: T.cap(context)),
        const SizedBox(height: 20),
        SecHead(tr('Why?')),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final r in ReturnReason.all) HChip(tr(returnReasonLabel(r)), on: vm.reason == r, onTap: () => vm.setReason(r))],
        ),
        const SizedBox(height: 14),
        HField(
          label: vm.reason == ReturnReason.other ? tr('What is wrong?') : tr('Details (optional)'),
          hint: tr('e.g. Expiry date was last month'),
          controller: note,
          multiline: true,
          name: 'note',
          errors: errors,
        ),
        const SizedBox(height: 14),
        ReturnPhotoPicker(photos: vm.photos, onChanged: vm.setPhotos),
        if (vm.units > 0) ...[
          const SizedBox(height: 16),
          HCard(color: c.surface2, child: KV(tr('{units} · value', {'units': plural(vm.units, 'unit')}), rs(vm.value))),
        ],
        // Room to scroll the last field above the footer button.
        const SizedBox(height: 96),
      ]),
    );
  }
}

/// Up to 6 photos of the problem.
class ReturnPhotoPicker extends StatelessWidget {
  const ReturnPhotoPicker({super.key, required this.photos, required this.onChanged});
  final List<String> photos;
  final ValueChanged<List<String>> onChanged;

  Future<void> _add(BuildContext context) async {
    final left = 6 - photos.length;
    if (left <= 0) return;
    final source = await showHSheet<ImageSource>(
      context,
      (ctx) => VStack(gap: 10, [
        SheetHead(tr('Add photos')),
        HButton(tr('Take a photo'), icon: 'camera', block: true, onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        HButton(tr('Choose from gallery'), icon: 'grid', block: true, kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
      ]),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final picked = source == ImageSource.camera
        ? [if (await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 82) case final x?) x]
        : await picker.pickMultiImage(maxWidth: 1600, imageQuality: 82, limit: left > 1 ? left : null);
    onChanged([...photos, for (final x in picked.take(left)) x.path]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Photos (optional)'), style: HField.labelStyle(context)),
        const SizedBox(height: 4),
        Text(tr('A photo of the expiry date or the damage helps HOLA decide faster. Up to {n}.', {'n': 6}), style: T.cap(context)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final (i, p) in photos.indexed) ...[
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(File(p), fit: BoxFit.cover),
                      ),
                      PositionedDirectional(
                        top: 4,
                        end: 4,
                        child: Tap(
                          onTap: () => onChanged([...photos]..removeAt(i)),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: const HIcon('x', size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (photos.length < 6)
                Tap(
                  onTap: () => _add(context),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.line),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        HIcon('camera', size: 22, color: c.brandText),
                        const SizedBox(height: 4),
                        Text(
                          tr('Add'),
                          style: T.cap(context).copyWith(color: c.ink, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── one return ──────────────────────────────────────────────────────────────

class ReturnDetailPage extends StatelessWidget {
  const ReturnDetailPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider(create: (c) => ReturnDetailViewModel(c.read<ReturnRepository>(), c.read<TradeRepository>(), c.read<AuthRepository>(), id), child: const _Detail());
}

class _Detail extends StatelessWidget {
  const _Detail();

  /// The steps this return goes through, ticked as far as it got.
  List<(String, bool, bool)> _steps(ReturnRequest r) {
    final s = r.status;
    final reached = {for (final h in r.history) h.status};
    final rank = [ReturnStatus.requested, ReturnStatus.underReview, ReturnStatus.awaitingSalon, ReturnStatus.approved, ReturnStatus.pickupAssigned, ReturnStatus.completed];
    final at = s == ReturnStatus.replacementCreated ? 5 : (s == ReturnStatus.responseSent ? 1 : rank.indexOf(s));
    final settled = switch (r.outcome) {
      SettlementType.creditAdjusted => tr('Outstanding adjusted'),
      SettlementType.voucher => tr('Voucher issued'),
      _ => tr('Replacement order sent'),
    };
    return [
      (tr('Return requested'), true, false),
      (tr('HOLA reviews it'), at >= 1 || reached.contains(ReturnStatus.underReview), at == 1),
      if (r.cod && r.option == ReturnOption.refund) (tr('You accept HOLA’s offer'), at >= 3, at == 2),
      (tr('Approved'), at >= 3, false),
      (tr('A rider collects the products'), at >= 5 || r.pickup?.collectedAt != null, at == 4),
      (settled, at >= 5, s == ReturnStatus.replacementCreated),
      if (r.outcome == SettlementType.replacement) (tr('Replacement delivered'), s == ReturnStatus.completed, false),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReturnDetailViewModel>();
    final r = vm.r;
    final c = context.c;
    if (r == null) {
      return HPage(
        title: tr('Return'),
        children: [EmptyState(icon: 'box', title: tr('Return not found'), text: tr('It may have been removed.'))],
      );
    }
    final (label, tone) = returnStatusLabel(r.status);
    final ended = r.status == ReturnStatus.rejected || r.status == ReturnStatus.cancelled;
    final actions = _actions(context, vm, r);
    return HPage(
      title: tr('Return {code}', {'code': r.code}),
      footer: actions.isEmpty ? null : VStack(gap: 8, actions),
      children: staggered([
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.code, style: T.h1(context)),
                  Text('${returnOptionLabel(r.option, cod: r.cod)} · ${tr(returnReasonLabel(r.reason))}', style: T.sub(context)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ToneBadge(label, tone: tone, live: r.status == ReturnStatus.awaitingSalon),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (r.status == ReturnStatus.awaitingSalon && r.proposal != null) ...[_Proposal(r.proposal!, mine: vm.isOwner), const SizedBox(height: 12)],
        if (r.settlement != null) ...[_SettlementCard(r.settlement!), const SizedBox(height: 12)],
        if (r.status == ReturnStatus.rejected)
          HCard(
            color: c.badSoft,
            child: Text(tr('HOLA rejected this return: {reason}', {'reason': r.rejectReason ?? ''}), style: T.sm(context).copyWith(color: c.badInk)),
          ),
        if (!ended)
          HCard(
            child: Column(
              children: [
                for (final (i, (t, done, cur)) in _steps(r).indexed)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done ? c.brand : (cur ? c.brandSoft : c.bg2),
                            border: cur ? Border.all(color: c.brand, width: 2) : null,
                          ),
                          alignment: Alignment.center,
                          child: done ? const HIcon('check', size: 13, stroke: 2.6, color: Colors.white) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(t, style: (done || cur ? T.ttl(context) : T.body(context)).copyWith(color: done || cur ? c.ink : c.subtle)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (r.pickup case final p?) ...[
          const SizedBox(height: 12),
          HCard(
            child: Row(
              children: [
                HIcon('truck', size: 22, color: c.brandText),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.collectedAt != null
                        ? tr('Collected by {rider} · {when}', {'rider': p.riderName, 'when': '${dLabel(p.collectedAt!)}, ${fmtTime(p.collectedAt!)}'})
                        : tr('Pickup assigned: {rider}', {'rider': p.riderName.isEmpty ? tr('a HOLA rider') : p.riderName}),
                    style: T.sm(context).copyWith(color: c.ink),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SecHead(tr('Products')),
        const SizedBox(height: 10),
        HCard(
          child: VStack(gap: 10, [
            for (final i in r.items)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text('${i.qty} × ${i.name}', style: T.sm(context).copyWith(color: c.ink)),
                  ),
                  const SizedBox(width: 12),
                  Text(rs(i.total), style: T.ttl(context)),
                ],
              ),
            const HDivider(),
            KV(tr('Value'), rs(r.amount)),
            if (r.approvedAmount != null && r.approvedAmount != r.amount) KV(tr('Approved'), rs(r.approvedAmount!), vColor: c.ok),
            KV(tr('Order'), r.orderCode),
            KV(tr('Payment'), r.cod ? tr('Cash on delivery') : tr('HOLA credit')),
          ]),
        ),
        if (r.note.isNotEmpty) ...[
          const SizedBox(height: 12),
          HCard(
            color: c.surface2,
            child: Text(r.note, style: T.sm(context)),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: HButton(
                tr('Message HOLA'),
                icon: 'msg',
                kind: BtnKind.secondary,
                onTap: () => r.conversationId != null ? pushPage(context, ChatPage(threadId: r.conversationId!)) : openHolaChat(context, salonId: r.salonId, returnId: r.id),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HButton(
                tr('See order'),
                icon: 'box',
                kind: BtnKind.secondary,
                onTap: () => pushPage(context, OrderDetailPage(id: r.orderId)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SecHead(tr('History')),
        const SizedBox(height: 10),
        HCard(
          child: VStack(gap: 10, [
            for (final h in r.history.reversed)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_eventText(h), style: T.ttl(context)),
                        Text(['${dLabel(h.at)}, ${fmtTime(h.at)}', if (h.by.isNotEmpty) h.by, if (h.note.isNotEmpty) h.note].join(' · '), style: T.cap(context)),
                      ],
                    ),
                  ),
                ],
              ),
          ]),
        ),
        SizedBox(height: 16 + 56.0 * (actions.length > 1 ? actions.length - 1 : 0)),
      ]),
    );
  }

  String _eventText(ReturnEvent h) => switch (h.action) {
    'CREDIT_ADJUSTED' => tr('Outstanding adjusted'),
    'VOUCHER' => tr('Voucher issued'),
    'REPLACEMENT' => tr('Replacement order created'),
    _ => returnStatusLabel(h.status).$1,
  };

  List<Widget> _actions(BuildContext context, ReturnDetailViewModel vm, ReturnRequest r) => [
    if (vm.canAnswer) ...[
      HButton(
        tr('Accept offer'),
        icon: 'check',
        kind: BtnKind.ok,
        block: true,
        onTap: () => attempt(vm.accept, success: tr('Offer accepted')),
      ),
      HButton(
        tr('Decline offer'),
        kind: BtnKind.ghost,
        block: true,
        small: true,
        onTap: () async {
          final note = await askText(context, title: tr('Decline HOLA’s offer?'), body: tr('Tell HOLA what would work for you instead.'), label: tr('Note'), confirm: tr('Decline'), minLength: 0);
          if (note != null) await attempt(() => vm.decline(note), success: tr('Sent to HOLA'));
        },
      ),
    ],
    if (vm.canCancel)
      HButton(
        tr('Withdraw request'),
        kind: BtnKind.ghost,
        block: true,
        small: true,
        onTap: () async {
          if (await confirmSheet(context, title: tr('Withdraw this return?'), body: tr('The products stay with you.'), confirm: tr('Withdraw'), danger: true)) {
            await attempt(vm.cancel, success: tr('Return withdrawn'), icon: 'x');
          }
        },
      ),
    // HOLA's team on the device (the dashboard does this for HOLA salons).
    if (vm.canReview) HButton(tr('Start review'), icon: 'clip', block: true, onTap: () => attempt(vm.review)),
    if (vm.canApprove)
      HButton(
        tr('Approve'),
        icon: 'check',
        kind: BtnKind.ok,
        block: true,
        onTap: () => attempt(vm.approve, success: tr('Approved')),
      ),
    if (vm.canPropose) ...[
      HButton(
        tr('Offer a voucher'),
        icon: 'cash',
        block: true,
        onTap: () => attempt(() => vm.propose(Settlement.voucher), success: tr('Offer sent')),
      ),
      HButton(
        tr('Offer a replacement'),
        icon: 'again',
        kind: BtnKind.secondary,
        block: true,
        onTap: () => attempt(() => vm.propose(Settlement.replace), success: tr('Offer sent')),
      ),
    ],
    if (vm.canAssignPickup) HButton(tr('Send a rider'), icon: 'truck', block: true, onTap: () => _pickRider(context, vm)),
    if (vm.canRespond)
      HButton(
        tr('Ask the salon'),
        icon: 'msg',
        kind: BtnKind.secondary,
        block: true,
        onTap: () async {
          final t = await askText(context, title: tr('Ask the salon'), label: tr('Message'), confirm: tr('Send'), minLength: 2);
          if (t != null) await attempt(() => vm.respond(t), success: tr('Sent'));
        },
      ),
    if (vm.canReject)
      HButton(
        tr('Reject'),
        kind: BtnKind.ghost,
        block: true,
        small: true,
        onTap: () async {
          final t = await askText(context, title: tr('Reject this return?'), label: tr('Reason'), confirm: tr('Reject'), danger: true, minLength: 3);
          if (t != null) await attempt(() => vm.reject(t), success: tr('Rejected'), icon: 'x');
        },
      ),
  ];

  Future<void> _pickRider(BuildContext context, ReturnDetailViewModel vm) async {
    final riders = vm.riders;
    final picked = await showHSheet<String>(
      context,
      (ctx) => VStack(gap: 14, [
        SheetHead(tr('Choose a rider'), sub: tr('They collect the products from the salon.')),
        if (riders.isEmpty)
          EmptyState(icon: 'truck', title: tr('No riders yet'), text: tr('Delivery riders appear here once they sign up for HOLA as a rider.'))
        else
          Group(
            children: [for (final x in riders) MRow(icon: 'truck', title: x.name, sub: x.phone, onTap: () => Navigator.pop(ctx, x.id))],
          ),
      ]),
    );
    if (picked != null) await attempt(() => vm.assignPickup(picked), success: tr('Rider assigned'), icon: 'truck');
  }
}

class _Proposal extends StatelessWidget {
  const _Proposal(this.p, {required this.mine});
  final ReturnProposal p;
  final bool mine;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final voucher = p.settlement == Settlement.voucher;
    return HCard(
      color: c.accentSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('HOLA’s offer'),
            style: T.cap(context).copyWith(color: c.accentInk, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(voucher ? tr('A voucher of {amount}', {'amount': rs(p.amount)}) : tr('Replace the products'), style: T.h3(context).copyWith(color: c.accentInk)),
          if (voucher && p.validUntil != null) Text(tr('Valid until {date}', {'date': dLabel(p.validUntil!)}), style: T.sm(context).copyWith(color: c.accentInk)),
          if (p.note.isNotEmpty) ...[const SizedBox(height: 6), Text(p.note, style: T.sm(context).copyWith(color: c.accentInk))],
          if (mine) ...[
            const SizedBox(height: 6),
            Text(
              voucher ? tr('If you accept, a rider collects the products and then your voucher is issued.') : tr('If you accept, a rider collects the products and HOLA sends new ones.'),
              style: T.cap(context).copyWith(color: c.accentInk),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard(this.s);
  final ReturnSettlement s;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return HCard(
      color: c.okSoft,
      child: switch (s.type) {
        SettlementType.creditAdjusted => Text(tr('{amount} was taken off your outstanding balance.', {'amount': rs(s.amount)}), style: T.ttl(context).copyWith(color: c.ok)),
        SettlementType.voucher when s.voucher != null => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Your voucher'),
              style: T.cap(context).copyWith(color: c.ok, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(s.voucher!.code, style: T.h2(context).copyWith(color: c.ok)),
                ),
                IconBtn(
                  'clip',
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: s.voucher!.code));
                    Fx.toast(tr('Voucher code copied'));
                  },
                ),
              ],
            ),
            Text(
              [
                rs(s.voucher!.amount),
                if (s.voucher!.validUntil != null) tr('valid until {date}', {'date': dLabel(s.voucher!.validUntil!)}),
              ].join(' · '),
              style: T.sm(context).copyWith(color: c.ok),
            ),
            const SizedBox(height: 4),
            Text(tr('Enter it under "Have a coupon?" on your next product order.'), style: T.cap(context).copyWith(color: c.ok)),
          ],
        ),
        _ => Tap(
          onTap: s.replacementOrderId == null ? null : () => pushPage(context, OrderDetailPage(id: s.replacementOrderId!)),
          child: Row(
            children: [
              Expanded(
                child: Text(tr('Replacement order {code}', {'code': s.replacementOrderCode ?? ''}), style: T.ttl(context).copyWith(color: c.ok)),
              ),
              HIcon('chev', size: 18, color: c.ok),
            ],
          ),
        ),
      },
    );
  }
}
