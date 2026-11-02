import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../trade/trade.dart';
import '../viewmodels/field_view_models.dart';
import 'salon_record_view.dart';

/// One visit: check in, then write the report (outcomes, notes, follow-up).
class VisitPage extends StatelessWidget {
  final String id;
  const VisitPage({super.key, required this.id});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => VisitViewModel(id, salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), field: c.read<FieldRepository>()),
        child: const _Body(),
      );
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VisitViewModel>();
    final v = vm.visit;
    if (v == null) return HPage(title: tr('Visit'), children: [EmptyState(icon: 'pin', title: tr('Visit not found'), text: tr('It may have been removed.'))]);
    final s = vm.salon(v.salonId);
    final c = context.c;
    final onDay = sameDay(v.plannedFor, today);

    final Widget? footer = switch (v.status) {
      VisitStatus.planned => Row(children: [
          Expanded(
            child: HButton(tr('Cancel visit'), kind: BtnKind.ghost, onTap: () async {
              if (await confirmSheet(context, title: tr('Cancel this visit?'), body: '${vm.salonName(v.salonId)} · ${dLabel(v.plannedFor)}, ${fmtTime(v.plannedFor)}', confirm: tr('Cancel visit'), danger: true, cancel: tr('Keep it'))) {
                await attempt(vm.cancel, success: tr('Visit cancelled'), icon: 'x');
              }
            }),
          ),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: HButton(tr('Check in'), icon: 'pin', onTap: onDay ? () => attempt(vm.checkIn, success: tr('Checked in at {time}', {'time': fmtTime(now())}), icon: 'pin') : null)),
        ]),
      VisitStatus.checkedIn => HButton(tr('Complete visit'), icon: 'check', block: true, kind: BtnKind.ok, onTap: () async {
          if (await attempt(vm.complete, success: vm.followUpAt == null ? tr('Visit saved') : tr('Visit saved · follow-up planned for {date}', {'date': dLabel(vm.followUpAt!)}))) {
            if (context.mounted) popPage(context);
          }
        }),
      _ => null,
    };

    return HPage(
      title: vm.salonName(v.salonId),
      footer: footer,
      children: staggered([
        const SizedBox(height: 4),
        if (v.status != VisitStatus.cancelled) ...[_Steps(step: switch (v.status) { VisitStatus.planned => 0, VisitStatus.checkedIn => 1, _ => 2 }), const SizedBox(height: 16)],
        HCard(
          onTap: s == null ? null : () => pushPage(context, SalonRecordPage(id: s.id)),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            SizedBox(width: 56, height: 56, child: SalonArt(s?.palette ?? 0, photo: s?.cover, n: 2, radius: 14, name: s?.name)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(vm.salonName(v.salonId), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                Text(vm.place(v.salonId), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context)),
                if (s != null) Padding(padding: const EdgeInsets.only(top: 6), child: StatusBadge(s.status)),
              ]),
            ),
            HIcon('chev', size: 18, color: c.subtle),
          ]),
        ),
        const SizedBox(height: 16),
        HCard(
          child: VStack(gap: 8, [
            KV(tr('Planned'), '${dayLabel(v.plannedFor, today)}, ${fmtTime(v.plannedFor)}'),
            KV(tr('Purpose'), tr(v.purpose)),
            if (v.checkInAt != null) KV(tr('Checked in'), fmtTime(v.checkInAt!)),
            if (v.completedAt != null) KV(tr('Completed'), '${dayLabel(v.completedAt!, today)}, ${fmtTime(v.completedAt!)}'),
            if (v.status == VisitStatus.cancelled) KV(tr('Status'), tr('Cancelled'), vColor: c.badInk),
          ]),
        ),
        const SizedBox(height: 16),
        ...switch (v.status) {
          VisitStatus.planned => [
              _Hint(
                icon: onDay ? 'pin' : 'clock',
                text: onDay ? tr('Check in when you arrive. Your check-in time is saved on the visit.') : v.plannedFor.isBefore(today) ? tr('This visit was missed. Cancel it or plan a new one.') : tr('Check-in opens on {date}.', {'date': dLabel(v.plannedFor)}),
              ),
            ],
          VisitStatus.checkedIn => [_Report(vm: vm, salon: s)],
          VisitStatus.completed => [_Summary(v: v)],
          _ => const <Widget>[],
        },
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// Check in → Report → Done, so the officer always knows the next step.
class _Steps extends StatelessWidget {
  final int step;
  const _Steps({required this.step});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final labels = [tr('Check in'), tr('Report'), tr('Done')];
    return Row(children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 6), color: i <= step ? c.brand : c.line)),
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(shape: BoxShape.circle, color: i < step ? c.brand : i == step ? c.brandSoft : c.bg2, border: i == step ? Border.all(color: c.brand, width: 1.5) : null),
          alignment: Alignment.center,
          child: i < step ? const HIcon('check', size: 14, stroke: 3, color: Colors.white) : Text('${i + 1}', style: T.cap(context).copyWith(color: i == step ? c.brandText : c.muted, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context).copyWith(color: i <= step ? c.ink : c.muted, fontWeight: i == step ? FontWeight.w700 : FontWeight.w500))),
      ],
    ]);
  }
}

class _Hint extends StatelessWidget {
  final String icon, text;
  const _Hint({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => HCard(
        color: context.c.surface2,
        child: Row(children: [
          HIcon(icon, size: 22, color: context.c.brandText),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: T.sm(context))),
        ]),
      );
}

class _Report extends StatefulWidget {
  final VisitViewModel vm;
  final Salon? salon;
  const _Report({required this.vm, required this.salon});
  @override
  State<_Report> createState() => _ReportState();
}

class _ReportState extends State<_Report> {
  late final _notes = TextEditingController(text: widget.vm.notes);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final s = widget.salon;
    return VStack(gap: 12, [
      SecHead(tr('Visit report')),
      Text(tr('1. What happened?'), style: T.sm(context).copyWith(color: context.c.ink, fontWeight: FontWeight.w600)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (k, label) in visitOutcomes) HChip(tr(label), on: vm.outcomes.contains(k), onTap: () => vm.toggleOutcome(k)),
      ]),
      HField(label: tr('2. Notes'), hint: tr('What did you discuss? Anything to follow up?'), controller: _notes, multiline: true, onChanged: (t) => vm.notes = t),
      Text(tr('3. Follow-up visit'), style: T.sm(context).copyWith(color: context.c.ink, fontWeight: FontWeight.w600)),
      Seg(
        opts: [('none', tr('None')), ('1w', tr('Next week')), ('2w', tr('2 weeks')), ('pick', vm.followUp == 'pick' && vm.pickedFollowUp != null ? dLabel(vm.pickedFollowUp!) : tr('Pick date'))],
        value: vm.followUp,
        onChanged: (v) async {
          if (v != 'pick') {
            vm.setFollowUp(v);
            return;
          }
          final d = await showDatePicker(context: context, initialDate: addDays(today, 3), firstDate: addDays(today, 1), lastDate: addDays(today, 180));
          if (d != null) vm.setFollowUp('pick', d);
        },
      ),
      if (vm.followUpAt != null) Text(tr('A follow-up visit will be planned for {date}, {time}.', {'date': dLabel(vm.followUpAt!), 'time': fmtTime(vm.followUpAt!)}), style: T.cap(context)),
      if (s != null && s.isActive) HButton(tr('Take an order'), icon: 'box', block: true, kind: BtnKind.secondary, onTap: () => pushPage(context, NewOrderPage(salonId: s.id))),
    ]);
  }
}

class _Summary extends StatelessWidget {
  final Visit v;
  const _Summary({required this.v});
  @override
  Widget build(BuildContext context) => VStack(gap: 12, [
        SecHead(tr('Report')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in v.outcomes) ToneBadge(tr(visitOutcomes.firstWhere((x) => x.$1 == o, orElse: () => (o, o)).$2), tone: o == 'NOT_INTERESTED' ? 'bad' : 'ok'),
        ]),
        if (v.notes.isNotEmpty) HCard(child: Text(v.notes, style: T.sm(context))),
        if (v.followUpAt != null) KV(tr('Follow-up'), '${dLabel(v.followUpAt!)}, ${fmtTime(v.followUpAt!)}'),
      ]);
}
