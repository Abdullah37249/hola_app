import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/option_tile.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/booking_flow_view_model.dart';
import '../widgets/salon_cards.dart';
import '../widgets/slot_picker.dart';
import 'booking_detail_view.dart';

/// Professional → date & time → review, then a real booking request.
class BookingFlowPage extends StatelessWidget {
  final String salonId, branchId;
  final List<String> serviceIds;
  const BookingFlowPage({super.key, required this.salonId, required this.branchId, required this.serviceIds});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => BookingFlowViewModel(c.read<SalonRepository>(), c.read<AuthRepository>(), c.read<BookingRepository>(), salonId: salonId, branchId: branchId, serviceIds: serviceIds),
        child: const _FlowBody(),
      );
}

class _FlowBody extends StatefulWidget {
  const _FlowBody();
  @override
  State<_FlowBody> createState() => _FlowBodyState();
}

class _FlowBodyState extends State<_FlowBody> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _step(BookingFlowViewModel b, int d) {
    b.go(d);
    d > 0 ? Sfx.nav() : Sfx.back();
  }

  Future<void> _confirm(BookingFlowViewModel b) async {
    b.note = _note.text;
    Appointment? made;
    final ok = await attempt(() async => made = await b.confirm());
    if (!ok || !mounted || made == null) return;
    Sfx.success();
    if (made!.status == ApptStatus.confirmed) Fx.confetti();
    Navigator.of(context).pushAndRemoveUntil(HolaRoute(BookedPage(id: made!.id, anyPro: b.staffId == null)), (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.watch<BookingFlowViewModel>();
    final c = context.c;
    final s = b.salonInfo;
    return HPage(
      title: tr('Book at {salon}', {'salon': s?.name ?? tr('salon')}),
      footer: Row(children: [
        if (b.step > 1) ...[SizedBox(width: 52, child: HButton('', icon: 'back', kind: BtnKind.soft, onTap: () => _step(b, -1), sound: false)), const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(rs(b.total), style: T.h3(context))),
            Text('${fmtDur(b.minutes)}${b.time != null && b.step > 1 ? ' · ${fmtTime(b.time!)}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(context).copyWith(color: c.muted)),
          ]),
        ),
        const SizedBox(width: 8),
        HButton(b.primaryLabel, icon: b.step == 3 ? 'check' : null, sound: b.step == 3, onTap: !b.canContinue ? null : () => b.step == 3 ? _confirm(b) : _step(b, 1)),
      ]),
      children: [
        Text(tr('STEP {n} OF 3', {'n': b.step}), style: T.eyebrow(context).copyWith(color: c.brandText)),
        const SizedBox(height: 8),
        HProgress(b.step / 3, height: 4),
        const SizedBox(height: 10),
        Row(children: [
          for (final (i, t) in BookingFlowViewModel.steps.indexed)
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: T.cap(context).copyWith(fontWeight: FontWeight.w600, color: i < b.step ? c.brandText : c.subtle),
                child: Text(tr(t), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: i == 0 ? TextAlign.left : i == 1 ? TextAlign.center : TextAlign.right),
              ),
            ),
        ]),
        const SizedBox(height: 26),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(.06, 0), end: Offset.zero).animate(a), child: child)),
          child: KeyedSubtree(key: ValueKey(b.step), child: _stepBody(context, b)),
        ),
      ],
    );
  }

  Widget _stepBody(BuildContext context, BookingFlowViewModel b) {
    final c = context.c;
    switch (b.step) {
      case 1:
        return VStack(gap: 10, [
          Text(tr('Who would you like?'), style: T.h1(context)),
          Text(tr('Pick a professional, or let the salon assign whoever is free first.'), style: T.body(context).copyWith(color: c.muted)),
          const SizedBox(height: 4),
          OptionTile(icon: 'users', title: tr('Any available professional'), sub: tr('Most open times'), on: b.staffId == null, onTap: () => b.setStaff(null)),
          for (final (p, name) in b.pros)
            OptionTile(
              title: name,
              sub: p.title.isEmpty ? tr('Professional') : p.title,
              on: b.staffId == p.accountId,
              onTap: () => b.setStaff(p.accountId),
              // Same layout as "Any available": picture on the left, selection on the right.
              leading: Avatar(name, size: 40, k: name.length),
            ),
        ]);
      case 2:
        return VStack(gap: 6, [
          Text(tr('Pick a time'), style: T.h1(context)),
          Text('${tr('{branch} branch', {'branch': b.branchInfo?.name ?? ''})}${b.staffName != null ? ' · ${tr('with {name}', {'name': b.staffName})}' : ''}', style: T.body(context).copyWith(color: c.muted)),
          const SizedBox(height: 12),
          SlotPicker(b),
        ]);
      default:
        final s = b.salonInfo;
        final br = b.branchInfo;
        final t = b.time!;
        return VStack(gap: 16, [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Review and book'), style: T.h1(context)),
            Text((s?.autoConfirm ?? false) ? tr('This salon confirms bookings instantly.') : tr("The salon confirms each request. We'll notify you."), style: T.body(context).copyWith(color: c.muted)),
          ]),
          HCard(
            child: VStack(gap: 10, [
              Row(children: [
                artThumb(s?.palette ?? 0, photo: s?.cover, 56, radius: 12, name: s?.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s?.name ?? '', style: T.ttl(context)),
                    if (br != null) Text([br.address, br.area].where((x) => x.isNotEmpty).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: T.sm(context).copyWith(color: c.muted)),
                  ]),
                ),
              ]),
              const HDivider(),
              KV(tr('Date'), dayLabel(t, today) == dLabel(t) ? dLabel(t) : '${dayLabel(t, today)}, ${dLabel(t)}'),
              KV(tr('Time'), '${fmtTime(t)} – ${fmtTime(t.add(Duration(minutes: b.minutes)))}'),
              KV(tr('Professional'), b.staffName ?? tr('First available')),
              const HDivider(),
              for (final x in b.services) KV(x.name, rs(x.price)),
              const HDivider(),
              Row(children: [
                Expanded(child: Text(tr('Total · pay at the salon'), style: T.ttl(context))),
                const SizedBox(width: 8),
                Text(rs(b.total), style: T.h2(context)),
              ]),
            ]),
          ),
          HCard(
            child: Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: c.okSoft, borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: HIcon('cash', size: 22, color: c.ok)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Pay at the salon'), style: T.ttl(context)),
                  Text(s == null || s.cancelWindowHours == 0 ? tr('Nothing to pay now.') : tr('Nothing to pay now. Free cancellation up to {hours} before.', {'hours': plural(s.cancelWindowHours, 'hour')}), style: T.sm(context).copyWith(color: c.muted)),
                ]),
              ),
            ]),
          ),
          HField(label: tr('Note for the salon (optional)'), hint: tr('Allergies, hair length, anything they should know'), controller: _note, multiline: true),
        ]);
    }
  }
}

/// Success screen after booking.
class BookedPage extends StatelessWidget {
  final String id;

  /// The client asked for any available professional, so the salon picked one.
  final bool anyPro;
  const BookedPage({super.key, required this.id, this.anyPro = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final a = context.read<BookingRepository>().appointment(id);
    final salons = context.read<SalonRepository>();
    final auth = context.read<AuthRepository>();
    if (a == null) return const SizedBox();
    final s = salons.salon(a.salonId);
    final confirmed = a.status == ApptStatus.confirmed;
    return HPage(
      title: '',
      alwaysTitle: false,
      children: [
        const SizedBox(height: 30),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: kSpring,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: confirmed ? G.ok : G.btn, boxShadow: [BoxShadow(color: (confirmed ? c.ok : c.brand).withValues(alpha: .35), blurRadius: 30, spreadRadius: -8, offset: const Offset(0, 14))]),
              alignment: Alignment.center,
              child: HIcon(confirmed ? 'check' : 'clock', size: 48, stroke: 2.4, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...staggered([
          Text(confirmed ? tr("You're booked") : tr('Request sent'), style: T.display(context), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(confirmed ? tr('{salon} has confirmed your appointment.', {'salon': s?.name ?? tr('The salon')}) : tr("{salon} will confirm shortly. We'll notify you as soon as they do.", {'salon': s?.name ?? tr('The salon')}), style: T.body(context).copyWith(color: c.muted), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          HCard(
            child: VStack(gap: 8, [
              KV(tr('Booking'), a.code),
              KV(tr('When'), '${dLabel(a.startsAt)}, ${fmtTime(a.startsAt)}'),
              KV(anyPro ? tr('Assigned to') : tr('With'), auth.account(a.staffId)?.name ?? tr('Assigned by salon')),
              Row(children: [Expanded(child: Text(tr('Status'), style: T.sm(context).copyWith(color: c.muted))), StatusBadge(a.status, label: customerStatusLabels[a.status] == null ? null : tr(customerStatusLabels[a.status]!))]),
            ]),
          ),
          const SizedBox(height: 18),
          HButton(tr('View booking'), block: true, onTap: () => replacePage(context, BookingDetailPage(id: a.id))),
          const SizedBox(height: 8),
          HButton(tr('Back to home'), kind: BtnKind.ghost, block: true, onTap: () {
            context.read<SessionViewModel>().setTab('home');
            popPage(context);
          }),
        ]),
      ],
    );
  }
}
