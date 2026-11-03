import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';

/// Provides a page-scoped [SalonViewModel] to [child].
class SalonScope extends StatelessWidget {
  final Widget child;
  const SalonScope({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: SalonViewModel.of, child: child);
}

/// Small pill with a count (unread, pending).
class CountPill extends StatelessWidget {
  final int n;
  final bool warn;
  const CountPill(this.n, {super.key, this.warn = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: warn ? context.c.accent : context.c.brand, borderRadius: BorderRadius.circular(11)),
      child: Text(
        '$n',
        style: const TextStyle(fontFamily: T.f, fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

/// Trailing for a menu row: a count pill when there is something, else a chevron.
Widget countOrChev(BuildContext context, int n, {bool warn = false}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    if (n > 0) ...[CountPill(n, warn: warn), const SizedBox(width: 6)],
    HIcon('chev', size: 18, color: context.c.subtle),
  ],
);

/// Where the salon stands with clients and with HOLA, and what is left to do.
/// Calm by default; changes requested / suspended stay prominent.
class VerificationBanner extends StatelessWidget {
  const VerificationBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final s = vm.salon;
    if (s == null || s.isActive) return const SizedBox.shrink();
    final c = context.c;

    if (s.status == SalonStatus.changes || s.status == SalonStatus.suspended) {
      final changes = s.status == SalonStatus.changes;
      return HCard(
        color: c.badSoft,
        border: Border.all(color: c.bad.withValues(alpha: .25)),
        shadow: const [],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HIcon('alert', size: 20, color: c.badInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(changes ? tr('HOLA asked for changes') : tr('Salon suspended'), style: T.ttl(context).copyWith(color: c.badInk)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.statusNote ?? (changes ? tr('Update your salon, then let HOLA know.') : tr('Clients can’t find or book you. Contact your HOLA sales officer.')),
              style: T.sm(context).copyWith(color: c.ink),
            ),
            if (changes) ...[const SizedBox(height: 12), HButton(tr("I've made the changes"), small: true, onTap: () => attempt(vm.resubmit, success: tr('Sent to HOLA for review')))],
          ],
        ),
      );
    }

    final live = vm.hasServices;
    Widget check(bool done, String label) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? c.ok : Colors.transparent,
              border: done ? null : Border.all(color: c.line, width: 1.5),
            ),
            alignment: Alignment.center,
            child: done ? const HIcon('check', size: 12, stroke: 3, color: Colors.white) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: T.sm(context).copyWith(color: done ? c.muted : c.ink, fontWeight: done ? FontWeight.w500 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return HCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: live ? c.ok : c.accent),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(live ? tr('Live for clients') : tr('Add a service to go live'), style: T.ttl(context))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            live
                ? tr('Clients can find and book {name}. HOLA verification is pending: it adds a Verified badge and unlocks product orders.', {'name': s.name})
                : tr('Clients can find you as soon as your menu has a service. HOLA verification adds a Verified badge later.'),
            style: T.sm(context).copyWith(color: c.muted),
          ),
          // Once everything is done, the checklist is just noise: show only what's left.
          if (!vm.hasServices) check(false, tr('Services and prices')),
          if (!vm.hasTeamHours) check(false, tr('Team working hours')),
          if (!vm.hasBranchHours) check(false, tr('Opening hours')),
        ],
      ),
    );
  }
}

/// Horizontal day picker.
class DayStrip extends StatelessWidget {
  final List<DateTime> days;
  final DateTime selected;
  final ValueChanged<DateTime> onPick;
  final bool Function(DateTime)? hasDot;
  final bool Function(DateTime)? disabled;
  const DayStrip({super.key, required this.days, required this.selected, required this.onPick, this.hasDot, this.disabled});
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 70 + 14 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final d = days[i];
          final off = disabled?.call(d) ?? false;
          return _DayPill(
            date: d,
            label: sameDay(d, today) ? tr('Today') : tr(const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]),
            on: sameDay(d, selected),
            dot: hasDot?.call(d) ?? false,
            off: off,
            onTap: off
                ? null
                : () {
                    Sfx.tap();
                    onPick(d);
                  },
          );
        },
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  final DateTime date;
  final String label;
  final bool on, dot, off;
  final VoidCallback? onTap;
  const _DayPill({required this.date, required this.label, required this.on, required this.dot, required this.off, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = on
        ? Colors.white
        : off
        ? c.subtle
        : c.ink;
    return Tap(
      onTap: onTap,
      sound: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: kEase,
        width: 58,
        margin: const EdgeInsets.only(bottom: 4),
        transform: Matrix4.translationValues(0, on ? -3 : 0, 0),
        decoration: BoxDecoration(
          gradient: on ? G.btn : null,
          color: on
              ? null
              : off
              ? c.bg2
              : c.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: on
              ? const [BoxShadow(color: Color(0x660B3566), blurRadius: 18, spreadRadius: -8, offset: Offset(0, 10))]
              : off
              ? null
              : c.lift,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, maxLines: 1, style: T.cap(context).copyWith(color: on ? Colors.white.withValues(alpha: .85) : c.muted)),
            Text('${date.day}', style: T.h3(context).copyWith(color: fg)),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot ? (on ? Colors.white : c.accent) : Colors.transparent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stepper with a formatted value and a custom step (durations, hours).
class ValueStepper extends StatelessWidget {
  final int value, min, max, step;
  final String Function(int) format;
  final ValueChanged<int> onChanged;
  const ValueStepper({super.key, required this.value, required this.onChanged, required this.format, this.min = 0, this.max = 999, this.step = 1});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget b(String ic, int d) {
      final v = value + d;
      final ok = v >= min && v <= max;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ok
            ? () {
                d > 0 ? Sfx.add() : Sfx.tap();
                onChanged(v);
              }
            : null,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: HIcon(ic, size: 18, color: ok ? c.ink : c.subtle)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b('minus', -step),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64),
            child: Text(format(value), textAlign: TextAlign.center, style: T.ttl(context)),
          ),
          b('plus', step),
        ],
      ),
    );
  }
}

/// A labelled row with a control on the right (settings style).
class SettingRow extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget control;
  const SettingRow({super.key, required this.title, this.sub, required this.control});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.ttl(context)),
              if (sub != null) Text(sub!, style: T.cap(context)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        control,
      ],
    ),
  );
}

/// Asks for a time of day; returns minutes from midnight.
Future<int?> pickMinutes(BuildContext context, int initial, {String help = 'Select time'}) async {
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    helpText: tr(help),
  );
  return t == null ? null : t.hour * 60 + t.minute;
}

/// Seven weekday rows, each off or a start–end window (team shifts, opening hours).
class WeekEditor extends StatelessWidget {
  final List<Shift?> week;
  final ValueChanged<List<Shift?>> onChanged;
  final String offLabel;
  const WeekEditor({super.key, required this.week, required this.onChanged, this.offLabel = 'Off'});
  static const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    void set(int i, Shift? s) => onChanged([...week]..[i] = s);
    Widget timeBtn(String label, VoidCallback onTap) => Tap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(10)),
        child: Text(
          label,
          style: T.sm(context).copyWith(color: c.brandText, fontWeight: FontWeight.w600),
        ),
      ),
    );
    return Group(
      children: [
        for (var i = 0; i < 7; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(tr(names[i]), style: T.ttl(context))),
                    if (week[i] == null) Text(tr(offLabel), style: T.sm(context).copyWith(color: c.muted)),
                    const SizedBox(width: 10),
                    HSwitch(on: week[i] != null, onChanged: (v) => set(i, v ? (week.whereType<Shift>().firstOrNull ?? const Shift(10 * 60, 19 * 60)) : null)),
                  ],
                ),
                if (week[i] case final s?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        timeBtn(fmtMin(s.start), () async {
                          final m = await pickMinutes(context, s.start, help: tr('{day} starts', {'day': tr(names[i])}));
                          if (m != null) set(i, Shift(m, s.end));
                        }),
                        Text(tr('to'), style: T.sm(context).copyWith(color: c.muted)),
                        timeBtn(fmtMin(s.end), () async {
                          final m = await pickMinutes(context, s.end, help: tr('{day} ends', {'day': tr(names[i])}));
                          if (m != null) set(i, Shift(s.start, m));
                        }),
                        if (s.end <= s.start) Text(tr('End must be after start'), style: T.cap(context).copyWith(color: c.badInk)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Compact weekly hours summary, e.g. "Mon–Sat 10:00 am – 8:00 pm".
String weekSummary(List<Shift?> week) {
  const d = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final parts = <String>[];
  var i = 0;
  while (i < 7) {
    final s = week[i];
    if (s == null) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < 7 && week[j + 1]?.start == s.start && week[j + 1]?.end == s.end) {
      j++;
    }
    parts.add('${j == i ? tr(d[i]) : '${tr(d[i])}–${tr(d[j])}'} ${fmtMin(s.start)}–${fmtMin(s.end)}');
    i = j + 1;
  }
  return parts.isEmpty ? tr('No hours set') : parts.join(' · ');
}

/// Bar showing a shift within the salon's day (team list).
class ShiftBar extends StatelessWidget {
  final Shift? shift;
  final int dayStart, dayEnd;
  const ShiftBar({super.key, required this.shift, this.dayStart = 8 * 60, this.dayEnd = 22 * 60});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final span = (dayEnd - dayStart).toDouble();
    return LayoutBuilder(
      builder: (_, k) {
        final w = k.maxWidth;
        return SizedBox(
          height: 8,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(color: c.bg2, borderRadius: BorderRadius.circular(4)),
              ),
              if (shift case final s?)
                Positioned(
                  left: w * ((s.start - dayStart).clamp(0, span) / span),
                  width: w * ((s.end - s.start).clamp(0, span) / span),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(gradient: G.btn, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One appointment as a card (Today, My day, requests): who, what, when, price.
class ApptRow extends StatelessWidget {
  final Appointment a;
  final String staffName;
  final VoidCallback onTap;
  final Widget? actions;
  final bool showDay;
  const ApptRow({super.key, required this.a, required this.staffName, required this.onTap, this.actions, this.showDay = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final when = '${showDay || !sameDay(a.startsAt, today) ? '${dayLabel(a.startsAt, today)}, ' : ''}${fmtTime(a.startsAt)} · ${fmtDur(a.durationMin)}';
    return HCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(a.customerName, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                    Text(
                      a.serviceNames.join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.sm(context).copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Price and status stack on the right, so the time line below gets the full width.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(rs(a.price), style: T.ttl(context)),
                  const SizedBox(height: 6),
                  StatusBadge(a.status),
                  if (a.isWalkIn) ...[const SizedBox(height: 4), ToneBadge(tr('Walk-in'))],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: HIcon('clock', size: 16, color: c.brandText),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  staffName == 'you' ? when : '$when · ${tr('with {name}', {'name': staffName})}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.sm(context).copyWith(color: c.ink, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (actions != null) ...[const SizedBox(height: 14), actions!],
        ],
      ),
    );
  }
}

/// Confirm / Decline buttons for a booking request.
class RequestActions extends StatelessWidget {
  final Appointment a;
  const RequestActions(this.a, {super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.read<SalonViewModel>();
    return Row(
      children: [
        Expanded(
          child: HButton(
            tr('Decline'),
            kind: BtnKind.secondary,
            small: true,
            onTap: () async {
              final r = await askText(
                context,
                title: tr('Decline {name}?', {'name': a.customerName}),
                body: tr('They will be told the salon can’t take this booking.'),
                label: tr('Reason (shared with the client)'),
                hint: tr('e.g. Fully booked at that time'),
                confirm: tr('Decline booking'),
                danger: true,
              );
              if (r != null) await attempt(() => vm.decline(a.id, r), success: tr('Booking declined'), icon: 'x');
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: HButton(tr('Confirm'), small: true, onTap: () => attempt(() => vm.confirm(a.id), success: tr('Confirmed. {name} has been notified', {'name': a.customerName.split(' ').first}))),
        ),
      ],
    );
  }
}

/// Weekday shift text for one day, e.g. "10:00 am – 7:00 pm" or "Day off".
String shiftText(Shift? s) => s == null ? tr('Day off') : '${fmtMin(s.start)} – ${fmtMin(s.end)}';
