import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../chat/chat.dart';
import '../../notifications/notifications.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';
import 'appointment_view.dart';
import 'walk_in_sheet.dart';

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
    final unread = vm.unreadMessages;
    return BandView(role: 'salon', children: [
      ...staggered([
        TopHead(eyebrow: '${s.name} · ${dLabel(today)}', title: '${greeting(now())}, ${vm.me?.firstName ?? ''}', actions: const [NotificationBell()]),
        const SizedBox(height: 16),
        KpiRow([
          Kpi(tr('Bookings today'), vm.countOn(today), hl: true),
          Kpi(tr('Expected today'), vm.revenueOn(today), format: (v) => rs(v)),
          Kpi(tr('Waiting for answer'), reqs.length),
        ]),
        const SizedBox(height: 16),
        _QuickActions(unread: unread),
        if (!s.isActive) ...[const SizedBox(height: 16), const VerificationBanner()],
        const SizedBox(height: 28),
      ]),
      if (reqs.isNotEmpty) ...[
        Reveal(i: 5, child: SecHead(tr('Needs your answer'), action: reqs.length > 3 ? tr('All {n}', {'n': reqs.length}) : null, onAction: () => pushPage(context, const _RequestsPage()))),
        const SizedBox(height: 12),
        for (final (i, a) in reqs.take(3).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Reveal(i: 6 + i, child: ApptRow(a: a, showDay: true, staffName: vm.firstNameOf(a.staffId), onTap: () => pushPage(context, AppointmentDetailPage(id: a.id)), actions: RequestActions(a))),
          ),
        const SizedBox(height: 16),
      ],
      Reveal(i: 9, child: SecHead(tr('Up next today'), action: tr('Calendar'), onAction: () => context.read<SessionViewModel>().setTab('calendar'))),
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
            child: Reveal(i: 10 + i, child: ApptRow(a: a, staffName: vm.firstNameOf(a.staffId), onTap: () => pushPage(context, AppointmentDetailPage(id: a.id)))),
          ),
    ]);
  }
}

class _QuickActions extends StatelessWidget {
  final int unread;
  const _QuickActions({required this.unread});
  @override
  Widget build(BuildContext context) {
    final vm = context.read<SalonViewModel>();
    final c = context.c;
    Widget tile(String icon, String label, VoidCallback onTap, {int badge = 0}) => Expanded(
          child: HCard(
            onTap: onTap,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: HIcon(icon, size: 20, color: c.brandText),
                ),
                if (badge > 0) Positioned(right: -8, top: -6, child: CountPill(badge, warn: true)),
              ]),
              const SizedBox(height: 8),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context).copyWith(color: c.ink, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
    return Row(children: [
      tile('plus', tr('Walk-in'), () => showWalkInSheet(context, vm)),
      const SizedBox(width: 10),
      tile('msg', tr('Messages'), () => pushPage(context, const ChatInboxPage()), badge: unread),
      const SizedBox(width: 10),
      tile('users', tr('Team'), () => context.read<SessionViewModel>().setTab('team'), badge: vm.pendingLeave.length),
    ]);
  }
}

class _RequestsPage extends StatelessWidget {
  const _RequestsPage();
  @override
  Widget build(BuildContext context) => SalonScope(
        child: Builder(builder: (context) {
          final vm = context.watch<SalonViewModel>();
          final reqs = vm.requests();
          return HPage(title: tr('Booking requests'), children: [
            const SizedBox(height: 8),
            if (reqs.isEmpty) EmptyState(icon: 'check', title: tr('All answered'), text: tr('New booking requests will appear here.')),
            for (final (i, a) in reqs.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Reveal(i: i, child: ApptRow(a: a, showDay: true, staffName: vm.firstNameOf(a.staffId), onTap: () => pushPage(context, AppointmentDetailPage(id: a.id)), actions: RequestActions(a))),
              ),
          ]);
        }),
      );
}

/// Staff member's day: who is in the chair, what's next, their numbers.
class SStaffToday extends StatelessWidget {
  const SStaffToday({super.key});
  @override
  Widget build(BuildContext context) => const SalonScope(child: _StaffToday());
}

class _StaffToday extends StatelessWidget {
  const _StaffToday();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final me = vm.me;
    final s = vm.salon;
    if (me == null || s == null) return const SizedBox();
    final mine = vm.onDay(today, staffId: me.id);
    final cur = vm.current(me.id);
    final next = vm.upNext(staffId: me.id).where((a) => a.id != cur?.id).toList();
    final reqs = vm.requests(staffId: me.id);
    final shift = vm.profile(me.id)?.shiftOn(today);
    final off = vm.onLeave(me.id, today);
    return BandView(role: 'sstaff', children: [
      ...staggered([
        TopHead(eyebrow: '${s.name} · ${dLabel(today)}', title: '${greeting(now())}, ${me.firstName}', actions: const [NotificationBell()]),
        const SizedBox(height: 16),
        KpiRow([
          Kpi(tr('My clients today'), mine.where((a) => a.status == ApptStatus.completed || ApptStatus.holding.contains(a.status)).length, hl: true),
          Kpi(tr('Done'), mine.where((a) => a.status == ApptStatus.completed).length),
          Kpi(tr('My hours'), 0, format: (_) => off ? tr('Leave') : shift == null ? tr('Off') : '${fmtMin(shift.start).replaceAll(':00', '')}–${fmtMin(shift.end).replaceAll(':00', '')}'),
        ]),
      ]),
      const BandMark(),
      const SizedBox(height: 24),
      if (cur != null) ...[
        Reveal(i: 3, child: SecHead(tr('Now'))),
        const SizedBox(height: 12),
        Reveal(i: 4, child: ApptRow(a: cur, staffName: 'you', onTap: () => pushPage(context, AppointmentDetailPage(id: cur.id)), actions: _NowActions(cur))),
        const SizedBox(height: 24),
      ],
      if (reqs.isNotEmpty) ...[
        Reveal(i: 5, child: SecHead(tr('Needs an answer'))),
        const SizedBox(height: 12),
        for (final a in reqs)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: ApptRow(a: a, showDay: true, staffName: 'you', onTap: () => pushPage(context, AppointmentDetailPage(id: a.id)), actions: RequestActions(a))),
        const SizedBox(height: 14),
      ],
      Reveal(i: 6, child: SecHead(tr('Later today'), action: tr('Calendar'), onAction: () => context.read<SessionViewModel>().setTab('calendar'))),
      const SizedBox(height: 12),
      if (next.isEmpty)
        Reveal(
          i: 7,
          child: HCard(
            child: EmptyState(
              icon: off ? 'sun' : 'cal',
              title: off ? tr('You’re on leave today') : tr('No more appointments today'),
              text: off ? tr('Enjoy your day off.') : tr('Bookings assigned to you will show up here as soon as clients make them.'),
              cta: off ? null : HButton(tr('Add a walk-in'), icon: 'plus', kind: BtnKind.secondary, small: true, onTap: () => showWalkInSheet(context, vm)),
            ),
          ),
        )
      else
        for (final (i, a) in next.indexed)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Reveal(i: 7 + i, child: ApptRow(a: a, staffName: 'you', onTap: () => pushPage(context, AppointmentDetailPage(id: a.id))))),
    ]);
  }
}

/// The next step for the client in the chair.
class _NowActions extends StatelessWidget {
  final Appointment a;
  const _NowActions(this.a);
  @override
  Widget build(BuildContext context) {
    final vm = context.read<SalonViewModel>();
    return switch (a.status) {
      ApptStatus.confirmed => HButton(tr('Check in {name}', {'name': a.customerName.split(' ').first}), icon: 'check', block: true, small: true, onTap: () => attempt(() => vm.checkIn(a.id), success: tr('Checked in'))),
      ApptStatus.checkedIn => HButton(tr('Start service'), icon: 'scissors', block: true, small: true, onTap: () => attempt(() => vm.start(a.id), success: tr('Service started'))),
      ApptStatus.inService => HButton(tr('Complete'), icon: 'check', kind: BtnKind.ok, block: true, small: true, onTap: () => attempt(() => vm.complete(a.id), success: tr('Completed'), confetti: true)),
      _ => const SizedBox.shrink(),
    };
  }
}
