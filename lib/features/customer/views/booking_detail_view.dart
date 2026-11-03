import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../chat/chat.dart';
import '../viewmodels/booking_flow_view_model.dart';
import '../viewmodels/bookings_view_models.dart';
import '../widgets/booking_card.dart';
import '../widgets/salon_cards.dart';
import '../widgets/slot_picker.dart';
import 'feedback_view.dart';
import 'salon_view.dart';

class BookingDetailPage extends StatelessWidget {
  final String id;
  const BookingDetailPage({super.key, required this.id});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => BookingDetailViewModel(c.read<SalonRepository>(), c.read<AuthRepository>(), c.read<BookingRepository>(), c.read<EngagementRepository>(), id),
    child: const _DetailBody(),
  );
}

enum _Tl { done, cur, todo, bad }

class _DetailBody extends StatelessWidget {
  const _DetailBody();

  List<(String, String, _Tl)> _timeline(BookingDetailViewModel vm, Appointment a) {
    String at(String s) {
      final e = a.event(s);
      return e == null ? '' : '${dayLabel(e.at, today)}, ${fmtTime(e.at)}';
    }

    if (ApptStatus.finished.contains(a.status) && a.status != ApptStatus.completed) {
      final e = a.history.lastOrNull;
      final note = e?.note?.isNotEmpty == true ? e!.note! : '';
      return [
        (tr('Requested'), at(ApptStatus.requested), _Tl.done),
        if (a.event(ApptStatus.confirmed) != null) (tr('Confirmed by salon'), at(ApptStatus.confirmed), _Tl.done),
        (
          tr(customerStatusLabels[a.status] ?? statusLabel(a.status)),
          [at(a.status), if (note.isNotEmpty) note, if (a.lateCancel) tr('Late cancellation')].where((x) => x.isNotEmpty).join(' · '),
          _Tl.bad,
        ),
      ];
    }
    const flow = [ApptStatus.requested, ApptStatus.confirmed, ApptStatus.checkedIn, ApptStatus.completed];
    final labels = {ApptStatus.requested: tr('Requested'), ApptStatus.confirmed: tr('Confirmed by salon'), ApptStatus.checkedIn: tr('Checked in at salon'), ApptStatus.completed: tr('Completed')};
    final cur = flow.indexOf(a.status == ApptStatus.inService ? ApptStatus.checkedIn : a.status);
    return [
      for (final (i, f) in flow.indexed)
        (
          labels[f]!,
          i <= cur
              ? (f == ApptStatus.confirmed && a.event(f)?.byId == 'auto' ? tr('Instantly') : at(f))
              : (f == ApptStatus.checkedIn
                    ? tr('When you arrive')
                    : f == ApptStatus.completed
                    ? tr('After your service')
                    : tr('Waiting for the salon')),
          i < cur || (i == cur && f == ApptStatus.completed)
              ? _Tl.done
              : i == cur
              ? _Tl.cur
              : _Tl.todo,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BookingDetailViewModel>();
    final c = context.c;
    final a = vm.a;
    if (a == null) {
      return HPage(
        title: tr('Booking'),
        children: [
          const SizedBox(height: 60),
          EmptyState(icon: 'cal', title: tr('Booking not found'), text: tr('It may have been removed.')),
        ],
      );
    }
    final s = vm.s;
    final b = vm.b;
    final review = vm.review;
    final complaints = vm.complaints;
    // One clear next step, at the thumb: reschedule, rate, or book again.
    final Widget? footer = vm.isUpcoming
        ? HButton(tr('Reschedule'), icon: 'cal', block: true, onTap: () => _reschedule(context, vm, a))
        : vm.canReview
        ? HButton(tr('Rate your visit'), icon: 'star', block: true, onTap: () => showReviewSheet(context, s?.name ?? tr('the salon'), vm.addReview))
        : s != null && s.isListed
        ? HButton(
            tr('Book again'),
            icon: 'plus',
            block: true,
            onTap: () => pushPage(context, SalonPage(id: s.id)),
          )
        : null;
    return HPage(
      title: tr('Booking {code}', {'code': a.code}),
      footer: footer,
      children: [
        VStack(
          gap: 16,
          staggered([
            Tap(
              onTap: s == null ? null : () => pushPage(context, SalonPage(id: s.id)),
              child: Row(
                children: [
                  artThumb(s?.palette ?? 0, photo: s?.cover, 64, radius: 14, name: s?.name),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s?.name ?? tr('Salon'), maxLines: 2, overflow: TextOverflow.ellipsis, style: T.h1(context).copyWith(fontSize: 26)),
                        if (b != null) Text(tr('{branch} branch', {'branch': b.name}), style: T.sub(context)),
                        const SizedBox(height: 6),
                        CustomerStatus(a.status),
                      ],
                    ),
                  ),
                  HIcon('chev', size: 18, color: c.subtle),
                ],
              ),
            ),
            HCard(
              child: Column(children: [for (final (i, x) in _timeline(vm, a).indexed) _TlRow(x.$1, x.$2, x.$3, last: i == _timeline(vm, a).length - 1)]),
            ),
            HCard(
              child: VStack(gap: 10, [
                KV(tr('When'), '${dLabel(a.startsAt)}, ${fmtTime(a.startsAt)}'),
                KV(tr('Duration'), fmtDur(a.durationMin)),
                KV(tr('Professional'), vm.personName(a.staffId)),
                const HDivider(),
                for (final n in a.serviceNames) Text(n, style: T.sm(context).copyWith(color: c.ink)),
                const HDivider(),
                Row(
                  children: [
                    Expanded(child: Text(tr('Total · pay at the salon'), style: T.ttl(context))),
                    const SizedBox(width: 8),
                    Text(rs(a.price), style: T.h2(context)),
                  ],
                ),
                if (a.notes.isNotEmpty) ...[const HDivider(), KV(tr('Your note'), a.notes)],
              ]),
            ),
            if (b != null)
              HCard(
                child: Row(
                  children: [
                    HIcon('pin', size: 20, color: c.brandText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText([b.address, b.area, b.city].where((x) => x.isNotEmpty).join(', '), style: T.sm(context).copyWith(color: c.ink)),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                if (b != null && s != null) ...[
                  Expanded(
                    child: HButton(tr('Directions'), icon: 'nav', kind: BtnKind.secondary, onTap: () => _directions(s, b)),
                  ),
                  const SizedBox(width: 10),
                ],
                if (s != null && !vm.onServer)
                  Expanded(
                    child: HButton(tr('Message'), icon: 'msg', kind: BtnKind.secondary, onTap: () => openSalonChat(context, s.id)),
                  ),
              ],
            ),
            if (vm.isUpcoming) ...[
              HButton(tr('Cancel booking'), kind: BtnKind.dangerSoft, block: true, onTap: () => _cancel(context, vm, s)),
              if (s != null)
                Text(
                  vm.onServer
                      ? a.freeCancelUntil == null || vm.freeCancel && a.status == ApptStatus.requested
                            ? tr('You can cancel free of charge.')
                            : vm.freeCancel
                            ? tr('Free cancellation until {date}, {time}.', {'date': dLabel(a.freeCancelUntil!), 'time': fmtTime(a.freeCancelUntil!)})
                            : tr('Cancelling now counts as a late cancellation.')
                      : vm.freeCancel
                      ? s.cancelWindowHours == 0 || a.status == ApptStatus.requested
                            ? tr('You can cancel free of charge.')
                            : tr('Free cancellation until {date}, {time}.', {
                                'date': dLabel(a.startsAt.subtract(Duration(hours: s.cancelWindowHours))),
                                'time': fmtTime(a.startsAt.subtract(Duration(hours: s.cancelWindowHours))),
                              })
                      : tr("It's less than {hours} before your visit, so cancelling now counts as a late cancellation.", {'hours': plural(s.cancelWindowHours, 'hour')}),
                  style: T.cap(context),
                  textAlign: TextAlign.center,
                ),
            ],
            if (review != null) ...[
              SecHead(tr('Your review')),
              HCard(child: ReviewTile(review, salonName: s?.name)),
              if (review.pending)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr('HOLA checks every review before it’s public.'), style: T.cap(context)),
                ),
            ],
            if (complaints.isNotEmpty) ...[SecHead(tr('Your feedback')), for (final x in complaints) ComplaintCard(x, salonName: s?.name ?? tr('Salon'))],
            if (s != null && a.status != ApptStatus.requested)
              Center(
                child: TextButton(
                  onPressed: () => showComplaintSheet(context, salonId: s.id, salonName: s.name, appointmentId: a.id),
                  child: Text(tr('Report a problem with this visit'), style: T.link(context)),
                ),
              ),
          ]),
        ),
      ],
    );
  }

  Future<void> _directions(Salon s, Branch b) async {
    final q = Uri.encodeComponent('${s.name}, ${b.address}, ${b.area}, ${b.city}');
    final ok = await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'), mode: LaunchMode.externalApplication);
    if (!ok) Fx.toast(tr("Couldn't open Maps on this phone"), icon: 'alert', tone: 'bad');
  }

  Future<void> _cancel(BuildContext context, BookingDetailViewModel vm, Salon? s) async {
    final late = !vm.freeCancel;
    final reason = await askText(
      context,
      title: tr('Cancel this booking?'),
      body: late ? tr('This is a late cancellation. The salon will see it on your record.') : tr('The salon is told straight away and the time is released.'),
      label: tr('Reason (optional)'),
      hint: tr('e.g. Plans changed'),
      confirm: tr('Cancel booking'),
      danger: true,
    );
    if (reason == null) return;
    await attempt(() => vm.cancel(reason), success: tr('Booking cancelled'), icon: 'x');
  }

  Future<void> _reschedule(BuildContext context, BookingDetailViewModel vm, Appointment a) async {
    final bookings = context.read<BookingRepository>();
    await showHSheet(
      context,
      (ctx) => Owned<SlotPickerViewModel>(
        create: () => SlotPickerViewModel(vm.salons, vm.auth, bookings, branchId: a.branchId, serviceIds: a.serviceIds, staffId: a.staffId, rescheduling: a.id),
        dispose: (p) => p.dispose(),
        builder: (ctx, picker) => ListenableBuilder(
          listenable: picker,
          builder: (ctx, _) => VStack(gap: 14, [
            SheetHead(tr('Move your booking'), sub: tr('With {name}. Pick a new day and time.', {'name': vm.personName(a.staffId)})),
            Seg(
              opts: [('same', tr('Same professional')), ('any', tr('Anyone free'))],
              value: picker.staffId == null ? 'any' : 'same',
              onChanged: (v) => picker.setStaff(v == 'any' ? null : a.staffId),
            ),
            SlotPicker(picker),
            HButton(
              tr('Move to this time'),
              block: true,
              onTap: picker.time == null
                  ? null
                  : () async {
                      final ok = await attempt(() => vm.reschedule(picker.time!, picker.staffId), success: tr('Booking moved'), icon: 'cal');
                      if (ok && ctx.mounted) Navigator.pop(ctx);
                    },
            ),
          ]),
        ),
      ),
    );
  }
}

/// The rating sheet: stars and an optional comment, posted with [post].
Future<void> showReviewSheet(BuildContext context, String salonName, Future<void> Function(int stars, String text) post) async {
  var stars = 0;
  await showHSheet(
    context,
    (ctx) => Owned<TextEditingController>(
      create: TextEditingController.new,
      dispose: (c) => c.dispose(),
      builder: (ctx, text) => StatefulBuilder(
        builder: (ctx, set) => VStack(gap: 16, [
          SheetHead(tr('How was {salon}?', {'salon': salonName}), sub: tr('Your review is public and helps other customers choose.')),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  onTap: () {
                    Sfx.tap();
                    set(() => stars = i);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AnimatedScale(
                      scale: i <= stars ? 1.15 : 1,
                      duration: const Duration(milliseconds: 250),
                      curve: kSpring,
                      child: HIcon('star', size: 38, fill: i <= stars, color: i <= stars ? ctx.c.accent : ctx.c.line),
                    ),
                  ),
                ),
            ],
          ),
          Text([tr('Tap to rate'), tr('Poor'), tr('Fair'), tr('Good'), tr('Very good'), tr('Excellent')][stars], textAlign: TextAlign.center, style: T.ttl(ctx)),
          HField(label: tr('Tell others about your visit (optional)'), controller: text, multiline: true),
          HButton(
            tr('Post review'),
            block: true,
            onTap: stars == 0
                ? null
                : () async {
                    final ok = await attempt(() => post(stars, text.text), success: tr('Thanks for your review'), icon: 'star', confetti: stars >= 4);
                    if (ok && ctx.mounted) Navigator.pop(ctx);
                  },
          ),
        ]),
      ),
    ),
  );
}

class _TlRow extends StatelessWidget {
  final String title, sub;
  final _Tl state;
  final bool last;
  const _TlRow(this.title, this.sub, this.state, {required this.last});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final done = state == _Tl.done, bad = state == _Tl.bad, cur = state == _Tl.cur;
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
                  gradient: done
                      ? G.ok
                      : bad
                      ? G.danger
                      : null,
                  color: done || bad ? null : c.surface,
                  border: done || bad ? null : Border.all(color: cur ? c.brand : c.line, width: 2),
                  boxShadow: cur ? [BoxShadow(color: c.brand.withValues(alpha: .25), spreadRadius: 4)] : null,
                ),
                alignment: Alignment.center,
                child: done || bad ? HIcon(bad ? 'x' : 'check', size: 14, stroke: 3, color: Colors.white) : null,
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: done ? c.ok : c.line),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: T.ttl(context).copyWith(color: state == _Tl.todo ? c.muted : c.ink)),
                  if (sub.isNotEmpty) Text(sub, style: T.cap(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
