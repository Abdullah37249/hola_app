import 'package:flutter/material.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';

/// Adds a walk-in client for today: services, professional, start time.
Future<void> showWalkInSheet(BuildContext context, SalonViewModel vm) async {
  if (vm.activeServices.isEmpty) {
    Fx.toast(tr('Add services to your menu first'), icon: 'scissors', tone: 'warn');
    return;
  }
  final pros = vm.bookable;
  if (pros.isEmpty) {
    Fx.toast(tr('Make at least one team member bookable first'), icon: 'users', tone: 'warn');
    return;
  }
  await showHSheet(context, (ctx) => _WalkIn(vm: vm, pros: pros));
}

class _WalkIn extends StatefulWidget {
  final SalonViewModel vm;
  final List<StaffProfile> pros;
  const _WalkIn({required this.vm, required this.pros});
  @override
  State<_WalkIn> createState() => _WalkInState();
}

class _WalkInState extends State<_WalkIn> {
  final name = TextEditingController(), phone = TextEditingController();
  final picked = <String>{};
  late String staffId = widget.pros.first.accountId;
  late String branchId = widget.vm.branches.first.id;
  DateTime? start;

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  /// Now, rounded down to 5 minutes.
  DateTime get _now {
    final n = now();
    return DateTime(n.year, n.month, n.day, n.hour, n.minute - n.minute % 5);
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final c = context.c;
    final svcs = vm.activeServices;
    final dur = svcs.where((s) => picked.contains(s.id)).fold(0, (t, s) => t + s.durationMin);
    final price = svcs.where((s) => picked.contains(s.id)).fold(0, (t, s) => t + s.price);
    final slots = picked.isEmpty ? const <DateTime>[] : vm.slots(branchId: branchId, serviceIds: picked.toList(), staffId: staffId, day: today).map((s) => s.start).toList();
    final times = [_now, ...slots.where((t) => t.isAfter(_now))];
    if (start != null && !times.contains(start)) start = null;
    final ready = name.text.trim().length >= 2 && picked.isNotEmpty && start != null;

    return VStack(gap: 16, [
      SheetHead(tr('Add a walk-in'), sub: tr('For clients who come in without booking. It goes straight onto the calendar.')),
      HField(label: tr('Client name'), hint: tr('Full name'), icon: 'user', controller: name, onChanged: (_) => setState(() {})),
      HField(label: tr('Phone (optional)'), hint: '0300 1234567', icon: 'phone', controller: phone, keyboard: TextInputType.phone),
      if (vm.branches.length > 1) ...[
        Text(tr('Branch'), style: T.ttl(context)),
        ChipRow(
          children: [for (final b in vm.branches) HChip(b.name, on: b.id == branchId, onTap: () => setState(() => branchId = b.id))],
        ),
      ],
      Text(tr('Services'), style: T.ttl(context)),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in svcs) HChip('${s.name} · ${fmtDur(s.durationMin)}', on: picked.contains(s.id), onTap: () => setState(() => picked.contains(s.id) ? picked.remove(s.id) : picked.add(s.id))),
        ],
      ),
      if (widget.pros.length > 1) ...[
        Text(tr('Professional'), style: T.ttl(context)),
        ChipRow(
          children: [for (final p in widget.pros) HChip(vm.firstNameOf(p.accountId), on: p.accountId == staffId, onTap: () => setState(() => staffId = p.accountId))],
        ),
      ],
      Text(tr('Start time'), style: T.ttl(context)),
      if (picked.isEmpty)
        Text(tr('Pick a service to see free times.'), style: T.sm(context).copyWith(color: c.muted))
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, t) in times.indexed) HChip(i == 0 ? tr('Now · {time}', {'time': fmtTime(t)}) : fmtTime(t), on: start == t, onTap: () => setState(() => start = t)),
          ],
        ),
      if (picked.isNotEmpty) Text('${fmtDur(dur)} · ${rs(price)}', style: T.sm(context).copyWith(color: c.muted)),
      HButton(
        tr('Add to calendar'),
        icon: 'plus',
        block: true,
        onTap: !ready
            ? null
            : () async {
                final ok = await attempt(
                  () => vm.walkIn(branchId: branchId, name: name.text, phone: phone.text, serviceIds: picked.toList(), staffId: staffId, start: start!),
                  success: tr('Walk-in added for {time}', {'time': fmtTime(start!)}),
                );
                if (ok && context.mounted) Navigator.pop(context);
              },
      ),
    ]);
  }
}
