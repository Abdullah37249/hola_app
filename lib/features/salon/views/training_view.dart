import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';

/// Staff tab: HOLA Academy sessions to enrol in, and ones attended.
class SStaffTraining extends StatelessWidget {
  const SStaffTraining({super.key});
  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        return BandView(
          role: 'sstaff',
          children: [
            ...staggered([TopHead(title: tr('Training'), sub: tr('Sessions run by HOLA. Enrol to save your seat.'))]),
            const SizedBox(height: 18), // clear the curve under the subtitle
            const BandMark(),
            const SizedBox(height: 20),
            ..._trainingList(context, vm),
          ],
        );
      },
    ),
  );
}

/// Owner: same list as a pushed page.
class TrainingListPage extends StatelessWidget {
  const TrainingListPage({super.key});
  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        return HPage(title: tr('Training'), children: [const SizedBox(height: 8), ..._trainingList(context, vm)]);
      },
    ),
  );
}

List<Widget> _trainingList(BuildContext context, SalonViewModel vm) {
  final up = vm.upcomingTrainings;
  final past = vm.pastTrainings;
  return [
    Reveal(i: 2, child: SecHead(tr('Upcoming'))),
    const SizedBox(height: 12),
    if (up.isEmpty)
      Reveal(
        i: 3,
        child: HCard(
          child: EmptyState(icon: 'grad', title: tr('No sessions scheduled'), text: tr('When HOLA schedules a training session you’ll be notified and can enrol here.')),
        ),
      ),
    for (final (i, t) in up.indexed)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Reveal(
          i: 3 + i,
          child: TrainingCard(t, vm: vm),
        ),
      ),
    if (past.isNotEmpty) ...[
      const SizedBox(height: 16),
      SecHead(tr('Past sessions')),
      const SizedBox(height: 12),
      for (final t in past)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TrainingCard(t, vm: vm),
        ),
    ],
  ];
}

class TrainingCard extends StatelessWidget {
  final Training t;
  final SalonViewModel vm;
  const TrainingCard(this.t, {super.key, required this.vm});
  @override
  Widget build(BuildContext context) {
    final me = vm.me?.id;
    final enrolled = t.enrolled.contains(me);
    final open = t.status == 'SCHEDULED' && t.at.isAfter(now());
    return HCard(
      onTap: () => pushPage(context, TrainingPage(id: t.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: open ? context.c.brandSoft : context.c.bg2, borderRadius: BorderRadius.circular(13)),
                alignment: Alignment.center,
                child: HIcon('grad', size: 22, color: open ? context.c.brandText : context.c.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: T.ttl(context)),
                    Text('${dayLabel(t.at, today)}, ${fmtTime(t.at)} · ${fmtDur(t.durationMin)}', style: T.sm(context).copyWith(color: context.c.muted)),
                    Text(t.location, style: T.cap(context)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _badge(t, me),
            ],
          ),
          if (open) ...[
            const SizedBox(height: 12),
            enrolled
                ? HButton(
                    tr('Withdraw'),
                    kind: BtnKind.secondary,
                    small: true,
                    onTap: () => attempt(() => vm.withdraw(t.id), success: tr('You left {title}', {'title': t.title}), icon: 'x'),
                  )
                : HButton(
                    t.seatsLeft > 0 ? tr('Enrol · {seats} left', {'seats': plural(t.seatsLeft, 'seat')}) : tr('Session full'),
                    small: true,
                    onTap: t.seatsLeft > 0 ? () => attempt(() => vm.enrol(t.id), success: tr('Seat saved for {title}', {'title': t.title})) : null,
                  ),
          ],
        ],
      ),
    );
  }
}

Widget _badge(Training t, String? me) => switch (t.status) {
  'CANCELLED' => ToneBadge(tr('Cancelled'), tone: 'bad'),
  'COMPLETED' => t.attended.contains(me) ? ToneBadge(tr('Attended'), tone: 'ok') : ToneBadge(tr('Completed'), tone: 'mute'),
  _ =>
    t.enrolled.contains(me)
        ? ToneBadge(tr('Enrolled'), tone: 'info')
        : t.at.isAfter(now())
        ? const SizedBox.shrink()
        : ToneBadge(tr('Closed'), tone: 'mute'),
};

/// One training session.
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
        final me = vm.me?.id;
        final enrolled = t.enrolled.contains(me);
        final open = t.status == 'SCHEDULED' && t.at.isAfter(now());
        final c = context.c;
        return HPage(
          title: t.title,
          footer: open
              ? FootBar(
                  child: enrolled
                      ? HButton(
                          tr('Withdraw'),
                          kind: BtnKind.secondary,
                          block: true,
                          onTap: () => attempt(() => vm.withdraw(t.id), success: tr('You left {title}', {'title': t.title}), icon: 'x'),
                        )
                      : HButton(t.seatsLeft > 0 ? tr('Enrol') : tr('Session full'), block: true, onTap: t.seatsLeft > 0 ? () => attempt(() => vm.enrol(t.id), success: tr('Seat saved'), confetti: true) : null),
                )
              : null,
          children: [
            const SizedBox(height: 8),
            ...staggered([
              Row(
                children: [
                  Expanded(child: Text(t.title, style: T.h1(context))),
                  _badge(t, me),
                ],
              ),
              const SizedBox(height: 16),
              HCard(
                child: VStack(gap: 10, [
                  KV(tr('When'), '${dLabel(t.at)}, ${fmtTime(t.at)}'),
                  KV(tr('Length'), fmtDur(t.durationMin)),
                  KV(tr('Where'), t.location),
                  KV(tr('Trainer'), vm.nameOf(t.trainerId)),
                  KV(tr('Seats'), t.status == 'SCHEDULED' ? tr('{left} of {total} left', {'left': t.seatsLeft, 'total': t.seats}) : tr('{n} enrolled', {'n': t.enrolled.length})),
                ]),
              ),
              if (t.description.isNotEmpty) ...[const SizedBox(height: 16), SecHead(tr('About this session')), const SizedBox(height: 8), Text(t.description, style: T.body(context))],
              if (t.status == 'COMPLETED') ...[
                const SizedBox(height: 16),
                HCard(
                  color: t.attended.contains(me) ? c.okSoft : c.surface2,
                  child: Row(
                    children: [
                      HIcon(t.attended.contains(me) ? 'check' : 'clock', size: 22, color: t.attended.contains(me) ? c.ok : c.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.attended.contains(me)
                              ? tr('You attended this session.')
                              : enrolled
                              ? tr('You were enrolled but not marked as attending.')
                              : tr('This session has finished.'),
                          style: T.sm(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ]),
          ],
        );
      },
    ),
  );
}
