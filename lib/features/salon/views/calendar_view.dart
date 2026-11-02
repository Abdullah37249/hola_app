import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';
import 'appointment_view.dart';
import 'walk_in_sheet.dart';

const _px = 72.0; // pixels per hour

/// Day calendar with one column per professional. Staff see only their own.
class SalonCalendar extends StatelessWidget {
  const SalonCalendar({super.key});
  @override
  Widget build(BuildContext context) => const SalonScope(child: _Calendar());
}

class _Calendar extends StatefulWidget {
  const _Calendar();
  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  DateTime day = today;
  String? branchId;
  final _v = ScrollController(), _h = ScrollController();
  bool _scrolled = false;

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final rk = context.watch<SessionViewModel>().rk;
    final me = vm.me;
    if (me == null || vm.salon == null) return const SizedBox();
    final c = context.c;
    // Staff header: avatar + name; grows with the system font size.
    final headH = 30 + MediaQuery.textScalerOf(context).scale(17);
    final staffMode = rk == 'sstaff';
    final branches = vm.branches;
    final br = branches.where((b) => b.id == branchId).firstOrNull;
    var appts = vm.onDay(day, staffId: staffMode ? me.id : null);
    if (br != null) appts = appts.where((a) => a.branchId == br.id).toList();
    final colIds = staffMode ? [me.id] : {...vm.bookable.map((p) => p.accountId), ...appts.map((a) => a.staffId)}.toList();

    // Visible hours: opening hours of the day (all branches), stretched to fit bookings.
    final open = (br == null ? branches : [br]).map((b) => b.hoursOn(day)).whereType<Shift>();
    var h0 = open.isEmpty ? 9 : open.map((s) => s.start ~/ 60).reduce(math.min);
    var h1 = open.isEmpty ? 21 : open.map((s) => (s.end + 59) ~/ 60).reduce(math.max);
    for (final a in appts) {
      h0 = math.min(h0, a.startsAt.hour);
      h1 = math.max(h1, a.endsAt.hour + (a.endsAt.minute > 0 ? 1 : 0));
    }
    h1 = math.min(h1, 24);
    if (!_scrolled && sameDay(day, today)) {
      _scrolled = true;
      final target = ((now().hour - h0 - 1) * _px).clamp(0.0, double.infinity);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_v.hasClients) _v.jumpTo(math.min(target, _v.position.maxScrollExtent));
      });
    }

    final days = [for (var i = -1; i < 14; i++) addDays(today, i)];
    final top = MediaQuery.paddingOf(context).top;
    final closed = open.isEmpty;

    return Stack(children: [
      Column(children: [
        // The band sizes itself to the header, so the grid never sits on it.
        Stack(children: [
          Positioned.fill(child: Band(role: staffMode ? 'sstaff' : 'salon', height: double.infinity)),
          Padding(
          padding: EdgeInsets.fromLTRB(kGutter, top + 12, kGutter, 30),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Reveal(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(staffMode ? tr('MY CALENDAR') : tr('CALENDAR'), style: T.eyebrow(context).copyWith(color: Colors.white.withValues(alpha: .8))),
                    Text(dayLabel(day, today), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h1(context).copyWith(color: Colors.white)),
                  ]),
                ),
                HButton(tr('Walk-in'), icon: 'plus', kind: BtnKind.white, small: true, onTap: () => showWalkInSheet(context, vm)),
              ]),
            ),
            const SizedBox(height: 12),
            Reveal(
              i: 1,
              child: DayStrip(
                days: days,
                selected: day,
                hasDot: (d) => vm.onDay(d, staffId: staffMode ? me.id : null).any((a) => ApptStatus.holding.contains(a.status)),
                onPick: (d) => setState(() => day = d),
              ),
            ),
            if (!staffMode && branches.length > 1) ...[
              const SizedBox(height: 4),
              ChipRow(children: [
                HChip(tr('All branches'), on: br == null, onTap: () => setState(() => branchId = null)),
                for (final b in branches) HChip(b.name, on: b.id == br?.id, onTap: () => setState(() => branchId = b.id)),
              ]),
            ],
          ]),
        ),
        ]),
        Expanded(
          child: colIds.isEmpty
              ? EmptyState(icon: 'users', title: tr('No bookable team yet'), text: tr('Turn on “Takes bookings” for at least one person in Team.'))
              : LayoutBuilder(builder: (context, k) {
                  const gutter = 52.0;
                  final colW = math.max(116.0, (k.maxWidth - gutter - 8) / colIds.length);
                  final gridW = colW * colIds.length;
                  final height = (h1 - h0) * _px;
                  final n = now();
                  final nowY = sameDay(day, n) && n.hour >= h0 && n.hour < h1 ? (n.hour - h0 + n.minute / 60) * _px : null;

                  Widget column(String id) {
                    final mine = appts.where((a) => a.staffId == id).toList();
                    final shift = vm.profile(id)?.shiftOn(day);
                    final leave = vm.onLeave(id, day);
                    return Container(
                      width: colW,
                      height: height,
                      decoration: BoxDecoration(border: Border(left: BorderSide(color: c.line))),
                      child: Stack(children: [
                        // Outside working hours is shaded.
                        if (leave || shift == null)
                          Positioned.fill(child: Container(color: c.bg2.withValues(alpha: .7)))
                        else ...[
                          Positioned(top: 0, left: 0, right: 0, height: ((shift.start / 60 - h0) * _px).clamp(0, height), child: Container(color: c.bg2.withValues(alpha: .7))),
                          Positioned(top: ((shift.end / 60 - h0) * _px).clamp(0, height), left: 0, right: 0, bottom: 0, child: Container(color: c.bg2.withValues(alpha: .7))),
                        ],
                        for (var h = 0; h < h1 - h0; h++) Positioned(top: h * _px, left: 0, right: 0, child: Container(height: 1, color: c.line.withValues(alpha: .6))),
                        if (leave) Positioned(top: 8, left: 6, right: 6, child: Text(tr('On leave'), textAlign: TextAlign.center, style: T.cap(context))),
                        for (final (i, a) in mine.indexed)
                          Positioned(
                            top: (a.startsAt.hour - h0 + a.startsAt.minute / 60) * _px + 1,
                            left: 3,
                            right: 3,
                            height: math.max(a.durationMin / 60 * _px - 3, 22),
                            child: Reveal(i: i, child: _ApptBlock(a)),
                          ),
                      ]),
                    );
                  }

                  return SingleChildScrollView(
                    controller: _v,
                    padding: EdgeInsets.only(bottom: 128 + MediaQuery.paddingOf(context).bottom),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (appts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                            child: Row(children: [
                              HIcon(closed ? 'clock' : 'cal', size: 18, color: c.muted),
                              const SizedBox(width: 10),
                              Expanded(child: Text(closed ? tr('The salon is closed on {day}.', {'day': dLabel(day)}) : sameDay(day, today) ? tr('No bookings on today yet. Tap Walk-in to add one.') : tr('No bookings on {day} yet. Tap Walk-in to add one.', {'day': dLabel(day)}), style: T.sm(context).copyWith(color: c.muted))),
                            ]),
                          ),
                        ),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // hour labels
                        SizedBox(
                          width: gutter,
                          child: Column(children: [
                            SizedBox(height: headH),
                            for (var h = h0; h < h1; h++)
                              SizedBox(height: _px, child: Align(alignment: Alignment.topCenter, child: Text(fmtMin(h * 60).replaceAll(':00', ''), style: T.cap(context).copyWith(fontSize: 11)))),
                          ]),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _h,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: gridW,
                              child: Column(children: [
                                SizedBox(
                                  height: headH,
                                  child: Row(children: [
                                    for (final id in colIds)
                                      SizedBox(
                                        width: colW,
                                        child: Column(children: [
                                          Avatar(vm.nameOf(id), size: 26),
                                          const SizedBox(height: 2),
                                          Text(vm.firstNameOf(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context).copyWith(color: c.ink, fontWeight: FontWeight.w600)),
                                        ]),
                                      ),
                                  ]),
                                ),
                                SizedBox(
                                  height: height,
                                  child: Stack(children: [
                                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final id in colIds) column(id)]),
                                    if (nowY != null)
                                      Positioned(
                                        top: nowY - 4,
                                        left: 0,
                                        right: 0,
                                        child: IgnorePointer(
                                          child: Row(children: [
                                            Container(width: 9, height: 9, decoration: BoxDecoration(color: c.bad, shape: BoxShape.circle)),
                                            Expanded(child: Container(height: 2, color: c.bad)),
                                          ]),
                                        ),
                                      ),
                                  ]),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ]),
                    ]),
                  );
                }),
        ),
      ]),
    ]);
  }
}

class _ApptBlock extends StatelessWidget {
  final Appointment a;
  const _ApptBlock(this.a);
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final live = a.status == ApptStatus.checkedIn || a.status == ApptStatus.inService;
    final req = a.status == ApptStatus.requested;
    final done = a.status == ApptStatus.completed;
    final gone = ApptStatus.finished.contains(a.status) && !done;
    final fg = live ? Colors.white : req ? c.accentInk : c.ink;
    return Tap(
      onTap: () => pushPage(context, AppointmentDetailPage(id: a.id)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 6, 4),
        decoration: BoxDecoration(
          gradient: live ? G.btn : req ? LinearGradient(colors: [c.accentSoft, Color.alphaBlend(c.accent.withValues(alpha: .22), c.surface)]) : null,
          color: live || req ? null : done ? c.okSoft : gone ? c.bg2 : c.brandSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(width: 3, color: live ? Colors.white : req ? c.accent : done ? c.ok : gone ? c.subtle : c.brand)),
          boxShadow: gone ? null : const [BoxShadow(color: Color(0x33000000), blurRadius: 10, spreadRadius: -6, offset: Offset(0, 4))],
        ),
        clipBehavior: Clip.hardEdge,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: T.f, fontSize: 12, fontWeight: FontWeight.w600, color: fg, decoration: gone ? TextDecoration.lineThrough : null)),
            if (a.durationMin >= 40) Text(a.serviceNames.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: T.f, fontSize: 11, color: fg.withValues(alpha: .8))),
            if (a.durationMin >= 60) Text(req ? tr('Needs answer') : '${fmtTime(a.startsAt)} – ${fmtTime(a.endsAt)}', maxLines: 1, style: TextStyle(fontFamily: T.f, fontSize: 11, color: fg.withValues(alpha: .8))),
          ]),
        ),
      ),
    );
  }
}
