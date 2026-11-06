import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/logo.dart';
import '../../../shared/widgets/option_tile.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/certificate_export.dart';
import '../widgets/salon_widgets.dart';

// HOLA Academy training for a salon: the salon account enrols itself and its
// team, and every session someone attends becomes a certificate.

/// Training hub as a pushed page.
class TrainingListPage extends StatefulWidget {
  const TrainingListPage({super.key});
  @override
  State<TrainingListPage> createState() => _TrainingListPageState();
}

class _TrainingListPageState extends State<TrainingListPage> {
  var _enrolled = false;
  @override
  void initState() {
    super.initState();
    context.read<FieldRepository>().syncTrainings(); // HOLA's latest sessions
  }

  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        return HPage(
          title: tr('Training'),
          onRefresh: context.read<FieldRepository>().syncTrainings,
          children: [
            const SizedBox(height: 8),
            Text(_intro, style: T.sm(context).copyWith(color: context.c.muted)),
            const SizedBox(height: 16),
            ..._hub(context, vm, enrolled: _enrolled, onSwitch: (v) => setState(() => _enrolled = v)),
          ],
        );
      },
    ),
  );
}

/// Training hub as the salon's Training tab.
class SalonTrainingTab extends StatefulWidget {
  const SalonTrainingTab({super.key});
  @override
  State<SalonTrainingTab> createState() => _SalonTrainingTabState();
}

class _SalonTrainingTabState extends State<SalonTrainingTab> {
  var _enrolled = false;
  @override
  void initState() {
    super.initState();
    context.read<FieldRepository>().syncTrainings(); // HOLA's latest sessions
  }

  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        return BandView(
          role: 'salon',
          onRefresh: context.read<FieldRepository>().syncTrainings,
          children: [
            ...staggered([TopHead(title: tr('Training'), sub: tr('Sessions run by the HOLA Academy and visiting trainers.'))]),
            const SizedBox(height: 18),
            ..._hub(context, vm, enrolled: _enrolled, onSwitch: (v) => setState(() => _enrolled = v), onBand: true),
          ],
        );
      },
    ),
  );
}

String get _intro => tr('Sessions run by the HOLA Academy. Enrol yourself and your team, and collect a certificate for each session attended.');

/// Upcoming sessions, or the ones the salon's people are enrolled in
/// (with their certificates), switched like Products' order views.
/// [onBand]: the switch sits on the header's edge, at the Today tab's height.
List<Widget> _hub(BuildContext context, SalonViewModel vm, {required bool enrolled, required ValueChanged<bool> onSwitch, bool onBand = false}) {
  final up = vm.upcomingTrainings;
  final past = vm.pastTrainings;
  final certs = vm.certificates;
  bool mine(Training t) => vm.enrolledHere(t).isNotEmpty || vm.attendedHere(t).isNotEmpty;
  final joined = [...up.where(mine), ...past.where(mine)];
  Widget card(int i, Training t) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Reveal(
      i: 3 + i,
      child: TrainingCard(t, vm: vm),
    ),
  );
  final seg = Seg(
    opts: [('up', tr('Upcoming')), ('mine', '${tr('Enrolled')}${joined.isNotEmpty ? ' · ${joined.length}' : ''}')],
    value: enrolled ? 'mine' : 'up',
    onChanged: (v) => onSwitch(v == 'mine'),
  );
  return [
    if (onBand) ...[BandMark(match: true, child: Reveal(i: 1, child: seg)), const SizedBox(height: 16)] else ...staggered([seg, const SizedBox(height: 16)], 1),
    if (!enrolled) ...[
      if (up.isEmpty)
        Reveal(
          i: 3,
          child: HCard(
            child: EmptyState(icon: 'grad', title: tr('No sessions scheduled'), text: tr('When HOLA schedules a training session you’ll be notified and can enrol your team here.')),
          ),
        ),
      for (final (i, t) in up.indexed) card(i, t),
    ] else ...[
      if (joined.isEmpty)
        Reveal(
          i: 3,
          child: HCard(
            child: EmptyState(
              icon: 'grad',
              title: tr('No enrolments yet'),
              text: tr('Enrol yourself or your team in an upcoming session. Attended sessions and certificates show here.'),
              cta: up.isEmpty ? null : HButton(tr('See upcoming'), kind: BtnKind.secondary, small: true, onTap: () => onSwitch(false)),
            ),
          ),
        ),
      for (final (i, t) in joined.indexed) card(i, t),
      if (certs.isNotEmpty) ...[
        const SizedBox(height: 14),
        SecHead(tr('Certificates')),
        const SizedBox(height: 12),
        Group(
          children: [for (final (t, id) in certs) CertificateRow(t, personId: id, vm: vm)],
        ),
      ],
    ],
  ];
}

/// "Starts in 3 h", "Tomorrow", "In 5 days" for an open session.
String _countdown(Training t) {
  final mins = t.at.difference(now()).inMinutes;
  final days = dateOnly(t.at).difference(today).inDays;
  if (mins < 60) return tr('Starts in {n} min', {'n': mins.clamp(1, 59)});
  if (days == 0) return tr('Starts in {n} h', {'n': mins ~/ 60});
  if (days == 1) return tr('Tomorrow');
  return tr('In {n} days', {'n': days});
}

Widget _badge(Training t, SalonViewModel vm) => switch (t.status) {
  'CANCELLED' => ToneBadge(tr('Cancelled'), tone: 'bad'),
  'COMPLETED' => vm.attendedHere(t).isNotEmpty ? ToneBadge(tr('Attended'), tone: 'ok') : ToneBadge(tr('Completed'), tone: 'mute'),
  _ =>
    vm.enrolledHere(t).isNotEmpty
        ? ToneBadge(tr('Enrolled'), tone: 'info')
        : vm.isOpen(t)
        ? const SizedBox.shrink()
        : ToneBadge(tr('Closed'), tone: 'mute'),
};

/// Calendar-page style date: month on top, big day number.
class DateTile extends StatelessWidget {
  final DateTime at;
  final bool live;
  final double size;
  const DateTile(this.at, {super.key, this.live = true, this.size = 56});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = live ? Colors.white : c.muted;
    return Container(
      width: size,
      height: size + 6,
      decoration: BoxDecoration(
        gradient: live ? G.btn : null,
        color: live ? null : c.bg2,
        borderRadius: BorderRadius.circular(14),
        boxShadow: live ? const [BoxShadow(color: Color(0x402F80FF), blurRadius: 14, spreadRadius: -6, offset: Offset(0, 8))] : null,
      ),
      // Large text: the date shrinks to fit the badge instead of spilling out.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(months[at.month - 1].toUpperCase(), style: T.eyebrow(context).copyWith(color: fg.withValues(alpha: .85), letterSpacing: 1, height: 1.2)),
            Text(
              '${at.day}',
              style: T.h1(context).copyWith(color: fg, fontSize: size * .46, height: 1.05),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filled-seats bar with "{left} of {total} seats left".
class SeatsBar extends StatelessWidget {
  final Training t;
  const SeatsBar(this.t, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final filled = t.seats == 0 ? 1.0 : (t.booked / t.seats).clamp(0.0, 1.0);
    final full = t.seatsLeft <= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                full ? tr('Session full') : tr('{left} of {total} seats left', {'left': t.seatsLeft, 'total': t.seats}),
                style: T.cap(context).copyWith(color: full ? c.bad : c.muted, fontWeight: FontWeight.w600),
              ),
            ),
            Text(tr('{n} enrolled', {'n': t.booked}), style: T.cap(context)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 7,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: c.bg2)),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: filled),
                  duration: const Duration(milliseconds: 700),
                  curve: kEase,
                  builder: (_, v, _) => FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: v,
                    child: DecoratedBox(decoration: BoxDecoration(gradient: full ? G.danger : G.flame)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One session: date tile, details, seats, who from the salon is going.
class TrainingCard extends StatelessWidget {
  final Training t;
  final SalonViewModel vm;
  const TrainingCard(this.t, {super.key, required this.vm});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final open = vm.isOpen(t);
    final done = t.status == 'COMPLETED';
    final going = vm.enrolledHere(t);
    final attended = vm.attendedHere(t);
    final people = done ? attended : going;
    final pill = switch (t.status) {
      'CANCELLED' => ToneBadge(tr('Cancelled'), tone: 'bad'),
      'COMPLETED' => ToneBadge(tr('Completed'), tone: 'ok'),
      _ when open => ToneBadge(t.seatsLeft > 0 ? tr('{n} left', {'n': plural(t.seatsLeft, 'seat')}) : tr('Session full'), tone: t.seatsLeft > 0 ? 'info' : 'warn'),
      _ => ToneBadge(tr('Closed'), tone: 'mute'),
    };
    return HCard(
      onTap: () => pushPage(context, TrainingPage(id: t.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.h3(context)),
              ),
              const SizedBox(width: 10),
              pill,
            ],
          ),
          const SizedBox(height: 4),
          Text(done ? tr('Completed {date}', {'date': '${t.at.day} ${months[t.at.month - 1]}'}) : '${dLabel(t.at)} · ${fmtTime(t.at)}', style: T.sm(context).copyWith(color: c.muted)),
          Text(
            t.location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.sm(context).copyWith(color: c.muted),
          ),
          if (people.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final id in people.take(3)) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: Avatar(vm.nameOf(id), size: 30)),
                const SizedBox(width: 4),
                Text(tr('{n} enrolled', {'n': people.length}), style: T.sm(context).copyWith(color: c.muted)),
              ],
            ),
          ],
          // Tap a name to enrol or withdraw them, straight from the card.
          if (open) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  for (final id in vm.people)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: _PersonChip(
                        name: id == vm.me?.id ? tr('You') : vm.nameOf(id).split(' ').first,
                        on: going.contains(id),
                        onTap: () {
                          final next = going.toSet();
                          if (!next.remove(id)) {
                            if (t.seatsLeft <= 0) return Fx.toast(tr('No seats left in this session'));
                            next.add(id);
                          }
                          attempt(() => vm.setEnrolled(t, next));
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (done && attended.isNotEmpty) ...[
            const SizedBox(height: 12),
            HButton(
              attended.length == 1 ? tr('View certificate') : tr('View certificates'),
              icon: 'doc',
              small: true,
              block: true,
              kind: BtnKind.secondary,
              onTap: () => pushPage(context, attended.length == 1 ? CertificatePage(trainingId: t.id, personId: attended.first) : TrainingPage(id: t.id)),
            ),
          ],
        ],
      ),
    );
  }
}

/// A team member's name as a pill; blue when they're enrolled.
class _PersonChip extends StatelessWidget {
  final String name;
  final bool on;
  final VoidCallback onTap;
  const _PersonChip({required this.name, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: on ? G.flame : null,
          color: on ? null : c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? Colors.transparent : c.line),
          boxShadow: on ? const [BoxShadow(color: Color(0x552F80FF), blurRadius: 14, spreadRadius: -6, offset: Offset(0, 6))] : null,
        ),
        child: Text(
          name,
          style: T.sm(context).copyWith(color: on ? Colors.white : c.ink, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Pick who from the salon goes to [t]; saves the difference.
Future<void> showEnrolSheet(BuildContext context, SalonViewModel vm, Training t) => showHSheet(context, (ctx) => _EnrolSheet(vm: vm, t: t));

class _EnrolSheet extends StatefulWidget {
  final SalonViewModel vm;
  final Training t;
  const _EnrolSheet({required this.vm, required this.t});
  @override
  State<_EnrolSheet> createState() => _EnrolSheetState();
}

class _EnrolSheetState extends State<_EnrolSheet> {
  late final Set<String> chosen = widget.vm.enrolledHere(widget.t).toSet();

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm, t = widget.t;
    final mine = vm.enrolledHere(t).length;
    final left = t.seatsLeft + mine - chosen.length; // seats left if saved now
    return VStack(gap: 10, [
      SheetHead(tr('Who’s going?'), sub: '${t.title} · ${dLabel(t.at)}, ${fmtTime(t.at)}'),
      for (final id in vm.people)
        OptionTile(
          leading: Avatar(vm.nameOf(id), size: 40),
          title: id == vm.me?.id ? tr('{name} (you)', {'name': vm.nameOf(id)}) : vm.nameOf(id),
          sub: id == vm.salon?.ownerId ? tr('Salon account') : vm.profile(id)?.title,
          on: chosen.contains(id),
          trailing: HIcon(chosen.contains(id) ? 'check' : 'plus', size: 20, color: chosen.contains(id) ? context.c.brand : context.c.subtle),
          onTap: () => setState(() {
            if (!chosen.remove(id)) {
              if (left <= 0) {
                Fx.toast(tr('No seats left in this session'));
              } else {
                chosen.add(id);
              }
            }
          }),
        ),
      const SizedBox(height: 2),
      Text(left <= 0 ? tr('No seats left in this session') : tr('{n} left after this', {'n': plural(left, 'seat')}), textAlign: TextAlign.center, style: T.cap(context)),
      HButton(
        chosen.isEmpty ? tr('Nobody from my salon') : tr('Save · {n} going', {'n': chosen.length}),
        block: true,
        onTap: () async {
          final ok = await attempt(
            () => vm.setEnrolled(t, chosen),
            success: chosen.isEmpty ? tr('Removed from {title}', {'title': t.title}) : tr('Seats saved for {title}', {'title': t.title}),
            confetti: chosen.length > mine,
          );
          if (ok && context.mounted) Navigator.pop(context);
        },
      ),
    ]);
  }
}

/// One training session in full.
class TrainingPage extends StatelessWidget {
  final String id;
  const TrainingPage({super.key, required this.id});
  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        final t = vm.training(id);
        if (t == null) {
          return HPage(
            title: tr('Training'),
            children: [EmptyState(icon: 'grad', title: tr('Session not found'), text: tr('It may have been removed.'))],
          );
        }
        final open = vm.isOpen(t);
        final going = vm.enrolledHere(t);
        final c = context.c;
        return HPage(
          title: t.title,
          footer: open
              ? FootBar(
                  child: HButton(
                    going.isEmpty ? (t.seatsLeft > 0 ? tr('Enrol team') : tr('Session full')) : tr('Change who’s going'),
                    icon: going.isEmpty ? 'plus' : 'users',
                    block: true,
                    onTap: going.isEmpty && t.seatsLeft <= 0 ? null : () => showEnrolSheet(context, vm, t),
                  ),
                )
              : null,
          children: [
            const SizedBox(height: 8),
            ...staggered([
              HCard(
                gradient: G.sun,
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
                      child: DateTile(t.at, size: 60),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('HOLA ACADEMY'), style: T.eyebrow(context).copyWith(color: Colors.white.withValues(alpha: .75))),
                          Text(t.title, style: T.h2(context).copyWith(color: Colors.white)),
                          const SizedBox(height: 4),
                          Text('${dLabel(t.at)} · ${fmtTime(t.at)}', style: T.sm(context).copyWith(color: Colors.white.withValues(alpha: .85))),
                          if (open) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(gradient: G.flame, borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                _countdown(t),
                                style: T.cap(context).copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            _badge(t, vm),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              HCard(
                child: VStack(gap: 10, [
                  KV(tr('Length'), fmtDur(t.durationMin)),
                  KV(tr('Where'), t.location),
                  KV(tr('Trainer'), t.trainerName.isNotEmpty ? t.trainerName : vm.nameOf(t.trainerId)),
                  if (open) SeatsBar(t) else KV(tr('Seats'), tr('{n} enrolled', {'n': t.booked})),
                ]),
              ),
              if (t.description.isNotEmpty) ...[const SizedBox(height: 20), SecHead(tr('About this session')), const SizedBox(height: 8), Text(t.description, style: T.body(context))],
              const SizedBox(height: 20),
              SecHead(tr('From your salon')),
              const SizedBox(height: 12),
              if (going.isEmpty)
                HCard(
                  color: c.surface2,
                  child: Row(
                    children: [
                      HIcon('users', size: 22, color: c.muted),
                      const SizedBox(width: 10),
                      Expanded(child: Text(open ? tr('Nobody from your salon is enrolled yet.') : tr('Nobody from your salon took part.'), style: T.sm(context))),
                    ],
                  ),
                )
              else
                Group(
                  children: [
                    for (final pid in going)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Avatar(vm.nameOf(pid), size: 38),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pid == vm.me?.id ? tr('{name} (you)', {'name': vm.nameOf(pid)}) : vm.nameOf(pid), style: T.ttl(context)),
                                  Text(switch (t.status) {
                                    'COMPLETED' => t.attended.contains(pid) ? tr('Attended · certificate ready') : tr('Not marked as attending'),
                                    'CANCELLED' => tr('Session cancelled'),
                                    _ => open ? tr('Seat saved') : tr('Waiting for attendance'),
                                  }, style: T.cap(context)),
                                ],
                              ),
                            ),
                            if (t.status == 'COMPLETED' && t.attended.contains(pid))
                              HButton(
                                tr('Certificate'),
                                icon: 'award',
                                small: true,
                                kind: BtnKind.secondary,
                                onTap: () => pushPage(context, CertificatePage(trainingId: t.id, personId: pid)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
            ]),
          ],
        );
      },
    ),
  );
}

/// Row in a certificates list: award icon, who, which session, when.
class CertificateRow extends StatelessWidget {
  final Training t;
  final String personId;
  final SalonViewModel vm;
  final bool showName;
  const CertificateRow(this.t, {super.key, required this.personId, required this.vm, this.showName = true});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => pushPage(context, CertificatePage(trainingId: t.id, personId: personId)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(gradient: G.flame, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const HIcon('award', size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(showName ? vm.nameOf(personId) : t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                Text(showName ? '${t.title} · ${dLabel(t.at)}' : '${dLabel(t.at)} · ${fmtDur(t.durationMin)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context)),
              ],
            ),
          ),
          HIcon('chev', size: 18, color: context.c.subtle),
        ],
      ),
    ),
  );
}

/// Training section on a team member's page: upcoming seats and certificates.
class MemberTraining extends StatelessWidget {
  final SalonViewModel vm;
  final String personId;
  const MemberTraining({super.key, required this.vm, required this.personId});
  @override
  Widget build(BuildContext context) {
    final up = vm.upcomingTrainings.where((t) => t.enrolled.contains(personId)).toList();
    final certs = vm.certificatesFor(personId);
    final mins = certs.fold(0, (m, t) => m + t.durationMin);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecHead(tr('Training'), action: certs.isEmpty ? null : fmtDur(mins)),
        const SizedBox(height: 12),
        if (up.isEmpty && certs.isEmpty)
          HCard(
            color: context.c.surface2,
            onTap: () => pushPage(context, const TrainingListPage()),
            child: Row(
              children: [
                HIcon('grad', size: 22, color: context.c.brandText),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('No training yet. Enrol them in a HOLA Academy session.'), style: T.sm(context))),
                HIcon('chev', size: 18, color: context.c.subtle),
              ],
            ),
          ),
        if (up.isNotEmpty)
          Group(
            children: [
              for (final t in up)
                InkWell(
                  onTap: () => pushPage(context, TrainingPage(id: t.id)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        DateTile(t.at, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                              Text('${fmtTime(t.at)} · ${_countdown(t)}', style: T.cap(context)),
                            ],
                          ),
                        ),
                        ToneBadge(tr('Enrolled'), tone: 'info'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        if (certs.isNotEmpty) ...[
          if (up.isNotEmpty) const SizedBox(height: 10),
          Group(
            children: [for (final t in certs) CertificateRow(t, personId: personId, vm: vm, showName: false)],
          ),
        ],
      ],
    );
  }
}

/// Certificate number: the session (from when HOLA created it) and the
/// person's place on its attendance list, which is fixed once marked.
String certificateNo(Training t, String personId) {
  // HOLA's own number once it issued the certificate.
  if (t.certificateOf[personId] case final no?) return no;
  final session = (t.createdAt.millisecondsSinceEpoch ~/ 1000 % 100000).toString().padLeft(5, '0');
  final seat = (t.attended.indexOf(personId) + 1).toString().padLeft(2, '0');
  return 'HOLA-${t.at.year}-$session-$seat';
}

/// A certificate of completion for one person and one session, which can be
/// saved to the phone or shared as a JPEG image or a PDF.
class CertificatePage extends StatefulWidget {
  final String trainingId, personId;
  const CertificatePage({super.key, required this.trainingId, required this.personId});
  @override
  State<CertificatePage> createState() => _CertificatePageState();
}

class _CertificatePageState extends State<CertificatePage> {
  final _paper = GlobalKey();
  String get personId => widget.personId;
  String get trainingId => widget.trainingId;
  bool _busy = false;

  /// Asks JPEG or PDF, then saves to the phone or opens the share sheet.
  Future<void> _run(BuildContext context, SalonViewModel vm, Training t, {required bool share}) async {
    final f = await showHSheet<CertFormat>(
      context,
      (ctx) => VStack(gap: 10, [
        SheetHead(share ? tr('Share certificate') : tr('Save certificate'), sub: share ? tr('Pick a format, then choose the app to send it with.') : tr('Pick a format to keep on this phone.')),
        Group(
          children: [
            MRow(icon: 'camera', title: tr('JPEG image'), sub: share ? tr('Best for WhatsApp and social media') : tr('Saved to your Gallery'), onTap: () => Navigator.pop(ctx, CertFormat.jpeg)),
            MRow(icon: 'file', title: tr('PDF document'), sub: share ? tr('Best for email and printing') : tr('Saved to Downloads'), onTap: () => Navigator.pop(ctx, CertFormat.pdf)),
          ],
        ),
      ]),
    );
    if (f == null || !context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size; // iPad share popover anchor
    final x = CertificateExport(_paper, fileName: 'HOLA-certificate-${certificateNo(t, personId)}', title: tr('{name} · {title} certificate', {'name': vm.nameOf(personId), 'title': t.title}));
    setState(() => _busy = true);
    try {
      if (share) {
        await x.share(f, origin: origin);
      } else {
        final where = await x.save(f);
        Sfx.success();
        Fx.toast(tr('Saved to {where}', {'where': where}), icon: 'check');
      }
    } catch (e) {
      Sfx.error();
      Fx.toast(isNoAccess(e) ? tr('Allow HOLA to add photos in Settings, then try again.') : tr('Couldn’t save the certificate. Try again.'), icon: 'alert', tone: 'bad');
      debugPrint('Certificate export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        final t = vm.training(trainingId);
        if (t == null || t.status != 'COMPLETED' || !t.attended.contains(personId)) {
          return HPage(
            title: tr('Certificate'),
            children: [EmptyState(icon: 'award', title: tr('No certificate'), text: tr('Certificates appear once HOLA marks attendance.'))],
          );
        }
        return HPage(
          title: tr('Certificate'),
          children: [
            const SizedBox(height: 8),
            Reveal(
              child: RepaintBoundary(
                key: _paper,
                child: _Certificate(
                  t: t,
                  name: vm.nameOf(personId),
                  salon: vm.salon?.name ?? '',
                  trainer: t.trainerName.isNotEmpty ? t.trainerName : vm.nameOf(t.trainerId),
                  no: certificateNo(t, personId),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Reveal(
              i: 1,
              child: Row(
                children: [
                  Expanded(
                    child: HButton(tr('Save'), icon: 'file', kind: BtnKind.secondary, block: true, onTap: _busy ? null : () => _run(context, vm, t, share: false)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Builder(
                      builder: (b) => HButton(tr('Share'), icon: 'ext', block: true, onTap: _busy ? null : () => _run(b, vm, t, share: true)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Reveal(
              i: 2,
              child: Text(tr('Save it to your phone or send it on WhatsApp, Gmail or Bluetooth, as an image or a PDF.'), textAlign: TextAlign.center, style: T.cap(context)),
            ),
          ],
        );
      },
    ),
  );
}

class _Certificate extends StatelessWidget {
  final Training t;
  final String name, salon, trainer, no;
  const _Certificate({required this.t, required this.name, required this.salon, required this.trainer, required this.no});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Light paper in both themes: a certificate reads like a printed page.
    const paper = Color(0xFFFFFCF6), ink = Color(0xFF13111C), muted = Color(0xFF6B6577), gold = Color(0xFFE08A1E);
    TextStyle s(TextStyle x) => x.copyWith(color: ink, decoration: TextDecoration.none);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFB866), Color(0xFF0A68BF), Color(0xFFFF8A00)]),
        borderRadius: BorderRadius.circular(22),
        boxShadow: c.liftHi,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(19)),
        child: Column(
          children: [
            const Logo(height: 30),
            const SizedBox(height: 18),
            Text(
              tr('CERTIFICATE OF COMPLETION'),
              textAlign: TextAlign.center,
              style: s(T.eyebrow(context)).copyWith(color: gold, letterSpacing: 2.2, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Text(tr('This certifies that'), style: s(T.sm(context)).copyWith(color: muted)),
            const SizedBox(height: 6),
            Text(name, textAlign: TextAlign.center, style: s(T.display(context))),
            if (salon.isNotEmpty)
              Text(
                salon,
                textAlign: TextAlign.center,
                style: s(T.sm(context)).copyWith(color: muted),
              ),
            const SizedBox(height: 14),
            Container(
              width: 60,
              height: 2,
              decoration: BoxDecoration(gradient: G.flame, borderRadius: BorderRadius.circular(1)),
            ),
            const SizedBox(height: 14),
            Text(
              tr('has completed the HOLA Academy session'),
              textAlign: TextAlign.center,
              style: s(T.sm(context)).copyWith(color: muted),
            ),
            const SizedBox(height: 4),
            Text(t.title, textAlign: TextAlign.center, style: s(T.h2(context))),
            const SizedBox(height: 4),
            Text(
              '${dLabel(t.at)} ${t.at.year} · ${fmtDur(t.durationMin)}',
              textAlign: TextAlign.center,
              style: s(T.sm(context)).copyWith(color: muted),
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trainer, maxLines: 1, overflow: TextOverflow.ellipsis, style: s(T.ttl(context))),
                      Container(margin: const EdgeInsets.symmetric(vertical: 4), height: 1, color: const Color(0x3313111C)),
                      Text(tr('HOLA trainer'), style: s(T.cap(context)).copyWith(color: muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: G.flame,
                    boxShadow: [BoxShadow(color: Color(0x662F80FF), blurRadius: 16, spreadRadius: -6, offset: Offset(0, 8))],
                  ),
                  alignment: Alignment.center,
                  child: const HIcon('award', size: 32, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(tr('Certificate no. {no}', {'no': no}), style: s(T.cap(context)).copyWith(color: muted, letterSpacing: .4)),
          ],
        ),
      ),
    );
  }
}
