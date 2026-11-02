import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/option_tile.dart';
import '../../../shared/widgets/ui.dart';

/// Animated ring: [done] of [total] in brand blue.
class ProgressRing extends StatelessWidget {
  final int done, total;
  final String label;
  final double size;
  const ProgressRing({super.key, required this.done, required this.total, this.label = 'visits', this.size = 92});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: total == 0 ? 0 : done / total),
          duration: const Duration(milliseconds: 1100),
          curve: kEase,
          builder: (_, v, _) => CustomPaint(
            painter: _RingPainter(v, context.c.bg2),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$done/$total', style: T.h3(context)),
                  Text(tr(label), style: T.cap(context)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color track;
  _RingPainter(this.v, this.track);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.shortestSide / 2 - 6);
    canvas.drawArc(r, 0, 2 * math.pi, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = track);
    if (v <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      2 * math.pi * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5E9BD6), Color(0xFF005BAC)]).createShader(r),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.v != v || o.track != track;
}

/// Equal-height row of KPI tiles.
class KpiStrip extends StatelessWidget {
  final List<Widget> tiles;
  const KpiStrip(this.tiles, {super.key});
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: tiles[i]),
          ],
        ]),
      );
}

/// "10:00 am – 8:00 pm" or "Closed".
String hoursText(Shift? s) => s == null ? tr('Closed') : '${fmtMin(s.start)} – ${fmtMin(s.end)}';

/// Weekday short names Mon..Sun (index 0 = Monday, matching Shift lists).
const weekdaysMon = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Salon list card used on Salons and in pickers.
class SalonTile extends StatelessWidget {
  final Salon salon;
  final String place, owner;
  final int services;
  final VoidCallback onTap;
  const SalonTile({super.key, required this.salon, required this.place, required this.owner, required this.services, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return HCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 56, height: 56, child: SalonArt(salon.palette, photo: salon.cover, n: 2, radius: 14, name: salon.name)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(salon.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
            Text([place, owner].where((x) => x.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(context).copyWith(color: c.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusBadge(salon.status),
              Text(plural(services, 'service'), style: T.cap(context)),
            ]),
          ]),
        ),
        Padding(padding: const EdgeInsets.only(top: 18), child: HIcon('chev', size: 18, color: c.subtle)),
      ]),
    );
  }
}

/// One visit in a list: time column, salon, purpose, status.
class VisitTile extends StatelessWidget {
  final Visit visit;
  final String salon, place;
  final VoidCallback onTap;
  final bool showDate;
  const VisitTile({super.key, required this.visit, required this.salon, required this.place, required this.onTap, this.showDate = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final v = visit;
    final (label, tone) = switch (v.status) {
      VisitStatus.completed => (tr('Completed'), 'ok'),
      VisitStatus.checkedIn => (tr('On visit'), 'info'),
      VisitStatus.cancelled => (tr('Cancelled'), 'bad'),
      _ => v.plannedFor.isBefore(today) ? (tr('Missed'), 'bad') : (tr('Planned'), 'mute'),
    };
    return Tap(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 64,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtTime(v.plannedFor), style: T.sm(context).copyWith(color: c.ink, fontWeight: FontWeight.w600)),
              if (showDate) Text(dayLabel(v.plannedFor, today), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context)),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(salon, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context).copyWith(decoration: v.status == VisitStatus.cancelled ? TextDecoration.lineThrough : null)),
              Text([place, tr(v.purpose)].where((x) => x.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context)),
            ]),
          ),
          const SizedBox(width: 8),
          ToneBadge(label, tone: tone, live: v.status == VisitStatus.checkedIn),
        ]),
      ),
    );
  }
}

/// Divider-separated card list.
class CardList extends StatelessWidget {
  final List<Widget> children;
  const CardList(this.children, {super.key});
  @override
  Widget build(BuildContext context) => HCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const HDivider(),
            children[i],
          ],
        ]),
      );
}

/// Sheet: pick a salon from [salons] (searchable). Returns its id.
Future<String?> pickSalon(BuildContext context, {required String title, required List<Salon> salons, String? note}) {
  final repo = context.read<SalonRepository>();
  var q = '';
  String place(Salon s) {
    final b = repo.branches(s.id).firstOrNull;
    return b == null ? '' : [b.area, b.city].where((x) => x.isNotEmpty).join(', ');
  }

  return showHSheet<String>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, set) {
      final list = salons.where((s) => '${s.name} ${place(s)}'.toLowerCase().contains(q.toLowerCase().trim())).toList();
      return VStack(gap: 10, [
        SheetHead(title, sub: note),
        if (salons.length > 5) HField(hint: tr('Search salons'), icon: 'search', onChanged: (v) => set(() => q = v)),
        if (salons.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text(tr('No salons available yet.'), textAlign: TextAlign.center, style: T.sm(ctx).copyWith(color: ctx.c.muted)))
        else if (list.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text(tr('No salon matches "{q}".', {'q': q}), textAlign: TextAlign.center, style: T.sm(ctx).copyWith(color: ctx.c.muted)))
        else
          for (final s in list.take(30))
            OptionTile(
              title: s.name,
              sub: place(s),
              on: false,
              trailing: HIcon('chev', size: 18, color: ctx.c.subtle),
              onTap: () => Navigator.pop(ctx, s.id),
            ),
      ]);
    }),
  );
}

/// Common visit purposes (quick picks; free text is allowed too).
const visitPurposes = ['Introduce HOLA', 'Verification', 'Take order', 'Collect payment', 'Training', 'Follow-up'];

/// Sheet: plan a visit. Picks the salon first when [salonId] is null.
Future<void> planVisitSheet(BuildContext context, {String? salonId, DateTime? day}) async {
  final salons = context.read<SalonRepository>();
  final field = context.read<FieldRepository>();
  final sid = salonId ?? await pickSalon(context, title: tr('Visit which salon?'), salons: salons.allSalons());
  if (sid == null || !context.mounted) return;
  final s = salons.salon(sid);
  if (s == null) return;

  final start = day != null && !day.isBefore(today) ? day : today;
  var date = start;
  var time = sameDay(start, today) ? TimeOfDay(hour: (now().hour + 1).clamp(9, 20), minute: 0) : const TimeOfDay(hour: 11, minute: 0);
  var purpose = '';
  final purposeCtl = TextEditingController();

  await showHSheet<void>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, set) {
      final c = ctx.c;
      Widget picker(String icon, String label, String value, VoidCallback onTap) => Expanded(
            child: HCard(
              onTap: onTap,
              color: c.bg2,
              shadow: const [],
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                HIcon(icon, size: 20, color: c.brandText),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: T.cap(ctx)),
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(ctx).copyWith(color: c.ink, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
          );
      return VStack(gap: 14, [
        SheetHead(tr('Plan a visit'), sub: s.name),
        Row(children: [
          picker('cal', tr('Date'), dayLabel(date, today), () async {
            final d = await showDatePicker(context: ctx, initialDate: date, firstDate: today, lastDate: addDays(today, 180));
            if (d != null) set(() => date = d);
          }),
          const SizedBox(width: 10),
          picker('clock', tr('Time'), time.format(ctx), () async {
            final t = await showTimePicker(context: ctx, initialTime: time);
            if (t != null) set(() => time = t);
          }),
        ]),
        Text(tr('Purpose'), style: T.sm(ctx).copyWith(color: c.ink, fontWeight: FontWeight.w600)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in visitPurposes)
            HChip(tr(p), on: purpose == p, onTap: () => set(() {
                  purpose = p;
                  purposeCtl.text = p;
                })),
        ]),
        HField(hint: tr('Or describe the purpose'), controller: purposeCtl, onChanged: (v) => set(() => purpose = v)),
        HButton(tr('Plan visit'), icon: 'pin', block: true, onTap: purpose.trim().length < 3
            ? null
            : () async {
                final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                final ok = await attempt(() => field.planVisit(salonId: sid, at: at, purpose: purpose), success: tr('Visit planned for {day}, {time}', {'day': sameDay(at, today) ? tr('today') : dLabel(at), 'time': fmtTime(at)}), icon: 'pin');
                if (ok && ctx.mounted) Navigator.pop(ctx);
              }),
      ]);
    }),
  );
}

/// Calm square icon tile (brand tint) used for quick actions and empty rows.
class IconTile extends StatelessWidget {
  final String icon;
  final double size;
  const IconTile(this.icon, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: context.c.brandSoft, borderRadius: BorderRadius.circular(size * .3)),
        alignment: Alignment.center,
        child: HIcon(icon, size: size * .5, color: context.c.brandText),
      );
}

/// Small rounded count, e.g. on "Needs attention" rows.
class CountPill extends StatelessWidget {
  final int n;
  final bool strong;
  const CountPill(this.n, {super.key, this.strong = true});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: strong ? c.brand : c.bg2, borderRadius: BorderRadius.circular(999)),
      alignment: Alignment.center,
      child: Text('$n', style: T.cap(context).copyWith(color: strong ? Colors.white : c.ink, fontWeight: FontWeight.w700)),
    );
  }
}

/// Opens a page pushed from a sheet-safe context.
void open(BuildContext context, Widget page) => pushPage(context, page);
