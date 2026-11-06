import 'package:flutter/material.dart';
import '../../../domain/repositories/repositories.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'clients_view.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../chat/chat.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';

/// One appointment from the salon's side, with every action its status allows.
class AppointmentDetailPage extends StatefulWidget {
  final String id;
  const AppointmentDetailPage({super.key, required this.id});
  @override
  State<AppointmentDetailPage> createState() => _AppointmentDetailPageState();
}

class _AppointmentDetailPageState extends State<AppointmentDetailPage> {
  @override
  void initState() {
    super.initState();
    // HOLA's timeline: who confirmed, moved or cancelled it, and why.
    context.read<BookingRepository>().syncBookingHistory(widget.id);
  }

  @override
  Widget build(BuildContext context) => SalonScope(child: _Detail(widget.id));
}

class _Detail extends StatelessWidget {
  final String id;
  const _Detail(this.id);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final a = vm.appointment(id);
    final c = context.c;
    if (a == null || a.salonId != vm.salonId) {
      return HPage(
        title: tr('Appointment'),
        children: [EmptyState(icon: 'cal', title: tr('Appointment not found'), text: tr('It may have been removed.'))],
      );
    }
    final branch = vm.branch(a.branchId);
    final chat = vm.canMessage(a);
    final first = a.customerName.split(' ').first;

    return HPage(
      title: a.code,
      footer: _footer(context, vm, a),
      children: [
        const SizedBox(height: 8),
        ...staggered([
          Row(
            children: [
              Avatar(a.customerName, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.customerName, style: T.h2(context)),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusBadge(a.status),
                        if (a.isWalkIn) ToneBadge(tr('Walk-in')),
                        if (a.lateCancel) ToneBadge(tr('Late cancel'), tone: 'bad'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (a.customerPhone.isNotEmpty || chat)
            Row(
              children: [
                if (a.customerPhone.isNotEmpty)
                  Expanded(
                    child: HButton(tr('Call'), icon: 'phone', kind: BtnKind.secondary, small: true, onTap: () => _call(context, a)),
                  ),
                if (a.customerPhone.isNotEmpty && chat) const SizedBox(width: 10),
                if (chat)
                  Expanded(
                    child: HButton(
                      tr('Message'),
                      icon: 'msg',
                      kind: BtnKind.secondary,
                      small: true,
                      onTap: () => openChat(context, salonId: a.salonId, customerId: a.customerId, appointmentId: a.id),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          _HistoryLink(a),
          const SizedBox(height: 20),
          // When, at a glance.
          HCard(
            gradient: G.sun,
            shadow: const [BoxShadow(color: Color(0x550B3566), blurRadius: 24, spreadRadius: -10, offset: Offset(0, 12))],
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dayLabel(a.startsAt, today).toUpperCase(), style: T.eyebrow(context).copyWith(color: Colors.white.withValues(alpha: .75))),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(fmtTime(a.startsAt), style: T.display(context).copyWith(color: Colors.white)),
                      ),
                      Text(tr('until {time} · {duration}', {'time': fmtTime(a.endsAt), 'duration': fmtDur(a.durationMin)}), style: T.sm(context).copyWith(color: Colors.white.withValues(alpha: .85))),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    Avatar(vm.nameOf(a.staffId), size: 40),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 72,
                      child: Text(
                        vm.firstNameOf(a.staffId),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.cap(context).copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          HCard(
            child: VStack(gap: 10, [
              if (vm.branches.length > 1 && branch != null) ...[KV(tr('Branch'), branch.name), const HDivider()],
              for (final n in a.serviceNames) Text(n, style: T.ttl(context)),
              const HDivider(),
              if (a.discount > 0) KV(tr('Offer discount'), '−${rs(a.discount)}', vColor: context.c.ok),
              KV(tr('Total, paid at salon'), rs(a.price)),
            ]),
          ),
          if (a.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            HCard(
              color: c.surface2,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HIcon('doc', size: 20, color: c.brandText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Note from {name}', {'name': first}), style: T.cap(context)),
                        Text(a.notes, style: T.sm(context)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          SecHead(tr('History')),
          const SizedBox(height: 10),
          HCard(
            child: Column(
              children: [for (final (i, e) in a.history.reversed.indexed) _Event(e, vm: vm, last: i == a.history.length - 1)],
            ),
          ),
        ]),
      ],
    );
  }

  void _call(BuildContext context, Appointment a) => showHSheet(
    context,
    (ctx) => VStack(gap: 16, [
      SheetHead(tr('Call {name}', {'name': a.customerName})),
      SelectableText(a.customerPhone, style: T.display(ctx)),
      HButton(
        tr('Copy number'),
        icon: 'clip',
        block: true,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: a.customerPhone));
          if (ctx.mounted) Navigator.pop(ctx);
          Fx.toast(tr('Number copied'));
        },
      ),
    ]),
  );

  Widget? _footer(BuildContext context, SalonViewModel vm, Appointment a) {
    Future<void> cancel() async {
      final r = await askText(
        context,
        title: tr('Cancel this appointment?'),
        body: a.customerId == null ? null : tr('{name} will be notified.', {'name': a.customerName}),
        label: tr('Reason'),
        hint: tr('e.g. Stylist unwell'),
        confirm: tr('Cancel appointment'),
        danger: true,
        minLength: 3,
      );
      if (r != null) await attempt(() => vm.cancel(a.id, r), success: tr('Appointment cancelled'), icon: 'x');
    }

    final more = HButton('', icon: 'grid', kind: BtnKind.soft, onTap: () => _moreSheet(context, vm, a, cancel));
    final Widget? main = switch (a.status) {
      ApptStatus.requested => RequestActions(a),
      ApptStatus.confirmed => Row(
        children: [
          SizedBox(width: 52, child: more),
          const SizedBox(width: 10),
          Expanded(
            child: vm.canMarkNoShow(a)
                ? HButton(
                    tr('Mark no-show'),
                    kind: BtnKind.dangerSoft,
                    block: true,
                    onTap: () async {
                      if (await confirmSheet(
                        context,
                        title: tr('Mark {name} as a no-show?', {'name': a.customerName}),
                        body: tr('They will be notified. This can’t be undone.'),
                        confirm: tr('Mark no-show'),
                        danger: true,
                      )) {
                        await attempt(() => vm.noShow(a.id), success: tr('Marked as no-show'), icon: 'alert');
                      }
                    },
                  )
                : a.startsAt.difference(now()).inMinutes > vm.checkInEarlyMin
                ? HButton(tr('Check-in opens {time}', {'time': fmtTime(a.startsAt.subtract(Duration(minutes: vm.checkInEarlyMin)))}), kind: BtnKind.soft, block: true, onTap: null)
                : HButton(
                    tr('Check in {name}', {'name': a.customerName.split(' ').first}),
                    icon: 'check',
                    block: true,
                    onTap: () => attempt(() => vm.checkIn(a.id), success: tr('Checked in')),
                  ),
          ),
          if (vm.canMarkNoShow(a)) ...[
            const SizedBox(width: 10),
            Expanded(
              child: HButton(
                tr('Arrived'),
                icon: 'check',
                block: true,
                onTap: () => attempt(() => vm.checkIn(a.id), success: tr('Checked in')),
              ),
            ),
          ],
        ],
      ),
      ApptStatus.checkedIn => Row(
        children: [
          Expanded(
            child: HButton(
              tr('Start service'),
              icon: 'scissors',
              block: true,
              onTap: () => attempt(() => vm.start(a.id), success: tr('Service started')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: HButton(
              tr('Complete'),
              kind: BtnKind.ok,
              block: true,
              onTap: () => attempt(() => vm.complete(a.id), success: tr('Completed'), confetti: true),
            ),
          ),
        ],
      ),
      ApptStatus.inService => HButton(
        tr('Complete service'),
        icon: 'check',
        kind: BtnKind.ok,
        block: true,
        onTap: () => attempt(() => vm.complete(a.id), success: tr('Completed'), confetti: true),
      ),
      _ => null,
    };
    return main == null ? null : FootBar(child: main);
  }

  void _moreSheet(BuildContext context, SalonViewModel vm, Appointment a, Future<void> Function() cancel) => showHSheet(
    context,
    (ctx) => VStack(gap: 10, [
      SheetHead(a.customerName, sub: '${dayLabel(a.startsAt, today)}, ${fmtTime(a.startsAt)}'),
      Group(
        children: [
          MRow(
            icon: 'cal',
            title: tr('Move to another time'),
            onTap: () {
              Navigator.pop(ctx);
              _reschedule(context, vm, a);
            },
          ),
          MRow(
            icon: 'x',
            title: tr('Cancel appointment'),
            tint: 1,
            titleColor: context.c.badInk,
            onTap: () {
              Navigator.pop(ctx);
              cancel();
            },
          ),
        ],
      ),
    ]),
  );

  void _reschedule(BuildContext context, SalonViewModel vm, Appointment a) => showHSheet(context, (ctx) => _Reschedule(vm: vm, a: a));
}

class _Event extends StatelessWidget {
  final StatusEvent e;
  final SalonViewModel vm;
  final bool last;
  const _Event(this.e, {required this.vm, required this.last});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = e.status == 'RESCHEDULED' ? tr('Moved') : tr(statusLabel(e.status));
    final by = e.byId == 'auto'
        ? tr('Confirmed automatically')
        : e.byId == 'system'
        ? 'HOLA'
        : vm.person(e.byId)?.name;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(gradient: G.btn, shape: BoxShape.circle),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 2), color: c.line),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: T.ttl(context)),
                  Text(['${dayLabel(e.at, today)}, ${fmtTime(e.at)}', ?by].join(' · '), style: T.cap(context)),
                  if (e.note != null && e.note!.isNotEmpty) Text(e.note!, style: T.sm(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reschedule extends StatefulWidget {
  final SalonViewModel vm;
  final Appointment a;
  const _Reschedule({required this.vm, required this.a});
  @override
  State<_Reschedule> createState() => _RescheduleState();
}

class _RescheduleState extends State<_Reschedule> {
  late DateTime day = dateOnly(widget.a.startsAt).isBefore(today) ? today : dateOnly(widget.a.startsAt);
  bool samePro = true;
  DateTime? pick;

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm, a = widget.a;
    final slots = vm.slots(branchId: a.branchId, serviceIds: a.serviceIds, staffId: samePro ? a.staffId : null, day: day, rescheduling: a.id);
    final days = [for (var i = 0; i < 21; i++) addDays(today, i)];
    return VStack(gap: 14, [
      SheetHead(tr('Move {name}’s appointment', {'name': a.customerName.split(' ').first}), sub: '${a.serviceNames.join(', ')} · ${fmtDur(a.durationMin)}'),
      DayStrip(
        days: days,
        selected: day,
        onPick: (d) => setState(() {
          day = d;
          pick = null;
        }),
      ),
      SettingRow(
        title: tr('Keep {name}', {'name': vm.firstNameOf(a.staffId)}),
        sub: tr('Off: any free professional'),
        control: HSwitch(
          on: samePro,
          onChanged: (v) => setState(() {
            samePro = v;
            pick = null;
          }),
        ),
      ),
      if (slots.isEmpty)
        Text(tr('No free times on {day}. Try another day.', {'day': dLabel(day)}), style: T.sm(context).copyWith(color: context.c.muted))
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final s in slots) HChip(fmtTime(s.start), on: pick == s.start, onTap: () => setState(() => pick = s.start))],
        ),
      HButton(
        tr('Move appointment'),
        block: true,
        onTap: pick == null
            ? null
            : () async {
                final ok = await attempt(() => vm.reschedule(a.id, pick!, staffId: samePro ? a.staffId : null), success: tr('Moved to {day}, {time}', {'day': dLabel(pick!), 'time': fmtTime(pick!)}));
                if (ok && context.mounted) Navigator.pop(context);
              },
      ),
    ]);
  }
}

/// "3 visits · Rs 4,500 — see history": this client's record at the salon.
class _HistoryLink extends StatelessWidget {
  const _HistoryLink(this.a);
  final Appointment a;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final key = vm.clientKeyOf(a);
    final cl = vm.client(key);
    if (cl == null) return const SizedBox();
    final sub = cl.completed == 0
        ? tr('First visit')
        : [
            plural(cl.completed, 'visit'),
            if (cl.spent > 0) rsShort(cl.spent),
            if (cl.lastVisit != null) tr('last {day}', {'day': dLabel(cl.lastVisit!)}),
          ].join(' · ');
    return Group(
      children: [
        MRow(
          icon: 'users',
          title: tr('Client history'),
          sub: sub,
          onTap: () => pushPage(context, ClientHistoryPage(clientKey: key)),
        ),
      ],
    );
  }
}
