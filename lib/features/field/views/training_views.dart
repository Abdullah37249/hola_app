import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../notifications/notifications.dart';
import '../../profile/profile.dart';
import '../viewmodels/field_view_models.dart';
import '../widgets/field_widgets.dart';

/// All training sessions the HOLA team runs, with "New session".
class TrainingsPage extends StatelessWidget {
  const TrainingsPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => TrainingsViewModel(salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), field: c.read<FieldRepository>()),
    child: const _ListBody(),
  );
}

class _ListBody extends StatelessWidget {
  const _ListBody();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TrainingsViewModel>();
    return HPage(
      title: tr('Training sessions'),
      onRefresh: context.read<FieldRepository>().syncTrainings,
      footer: HButton(tr('New session'), icon: 'plus', block: true, onTap: () => pushPage(context, const TrainingEditorPage())),
      children: staggered([
        if (vm.upcoming.isEmpty && vm.past.isEmpty)
          EmptyState(icon: 'grad', title: tr('No sessions yet'), text: tr('Schedule a training session. Salon owners and staff are notified and can enrol from their app.'))
        else ...[
          SecHead(tr('Upcoming'), action: vm.upcoming.isEmpty ? null : '${vm.upcoming.length}'),
          const SizedBox(height: 12),
          if (vm.upcoming.isEmpty)
            HCard(
              child: Text(tr('Nothing scheduled.'), style: T.sm(context).copyWith(color: context.c.muted)),
            )
          else
            for (final t in vm.upcoming) Padding(padding: const EdgeInsets.only(bottom: 10), child: TrainingCard(t)),
          if (vm.past.isNotEmpty) ...[
            const SizedBox(height: 24),
            SecHead(tr('Past')),
            const SizedBox(height: 12),
            for (final t in vm.past) Padding(padding: const EdgeInsets.only(bottom: 10), child: TrainingCard(t)),
          ],
        ],
      ]),
    );
  }
}

class TrainingCard extends StatelessWidget {
  final Training t;
  const TrainingCard(this.t, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (label, tone) = switch (t.status) {
      'COMPLETED' => (tr('Completed'), 'ok'),
      'CANCELLED' => (tr('Cancelled'), 'bad'),
      _ =>
        t.at.isBefore(now())
            ? (tr('Mark attendance'), 'warn')
            : t.seatsLeft <= 0
            ? (tr('Full'), 'warn')
            : (tr('{n} seats left', {'n': t.seatsLeft}), 'info'),
    };
    return HCard(
      onTap: () => pushPage(context, TrainingAdminPage(id: t.id)),
      child: Row(
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(gradient: t.status == 'SCHEDULED' ? G.btn : null, color: t.status == 'SCHEDULED' ? null : c.bg2, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Text(months[t.at.month - 1], style: T.cap(context).copyWith(color: t.status == 'SCHEDULED' ? Colors.white70 : null)),
                Text('${t.at.day}', style: T.h3(context).copyWith(color: t.status == 'SCHEDULED' ? Colors.white : null)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                Text('${fmtTime(t.at)} · ${t.location}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ToneBadge(label, tone: tone),
                    Text(tr('{n}/{seats} enrolled', {'n': t.booked, 'seats': t.seats}), style: T.cap(context)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Create or edit a training session.
class TrainingEditorPage extends StatefulWidget {
  final Training? existing;
  const TrainingEditorPage({super.key, this.existing});
  @override
  State<TrainingEditorPage> createState() => _EditorState();
}

class _EditorState extends State<TrainingEditorPage> {
  late final Training? t = widget.existing;
  late final title = TextEditingController(text: t?.title ?? '');
  late final desc = TextEditingController(text: t?.description ?? '');
  late final location = TextEditingController(text: t?.location ?? '');
  late DateTime date = t == null ? addDays(today, 7) : dateOnly(t!.at);
  late TimeOfDay time = t == null ? const TimeOfDay(hour: 11, minute: 0) : TimeOfDay.fromDateTime(t!.at);
  late int duration = t?.durationMin ?? 120;
  late int seats = t?.seats ?? 12;

  @override
  void dispose() {
    title.dispose();
    desc.dispose();
    location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final field = context.read<FieldRepository>();
    Widget picker(String icon, String label, String value, VoidCallback onTap) => Expanded(
      child: HCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            HIcon(icon, size: 20, color: c.brandText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: T.cap(context)),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.sm(context).copyWith(color: c.ink, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return HPage(
      title: t == null ? tr('New session') : tr('Edit session'),
      footer: HButton(
        t == null ? tr('Schedule session') : tr('Save changes'),
        icon: 'check',
        block: true,
        onTap: () async {
          final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
          final ok = await attempt(
            () => field.saveTraining(id: t?.id, title: title.text, description: desc.text, location: location.text, at: at, durationMin: duration, seats: seats),
            success: t == null ? tr('Session scheduled. Salons have been notified') : tr('Session updated'),
            icon: 'grad',
          );
          if (ok && context.mounted) popPage(context);
        },
      ),
      children: [
        VStack(gap: 14, [
          HField(label: tr('Title'), hint: tr('e.g. Colour Mastery: Level 2'), controller: title),
          HField(label: tr('What will people learn?'), hint: tr('Short description'), controller: desc, multiline: true),
          HField(label: tr('Location'), hint: tr('e.g. HOLA Academy, Gulberg'), controller: location, icon: 'pin'),
          Row(
            children: [
              picker('cal', tr('Date'), dLabel(date), () async {
                final d = await showDatePicker(context: context, initialDate: date.isBefore(today) ? today : date, firstDate: today, lastDate: addDays(today, 365));
                if (d != null) setState(() => date = d);
              }),
              const SizedBox(width: 10),
              picker('clock', tr('Starts'), time.format(context), () async {
                final x = await showTimePicker(context: context, initialTime: time);
                if (x != null) setState(() => time = x);
              }),
            ],
          ),
          HCard(
            child: VStack(gap: 12, [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Duration'),
                      style: T.sm(context).copyWith(color: c.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(fmtDur(duration), style: T.sm(context)),
                  const SizedBox(width: 10),
                  HStepper(value: duration ~/ 15, min: 1, max: 32, onChanged: (v) => setState(() => duration = v * 15)),
                ],
              ),
              const HDivider(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Seats'),
                      style: T.sm(context).copyWith(color: c.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                  HStepper(value: seats, min: 1, max: 200, onChanged: (v) => setState(() => seats = v)),
                ],
              ),
            ]),
          ),
          if (t == null) Text(tr('Every salon owner and staff member on HOLA gets a notification and can enrol.'), style: T.cap(context)),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// One session: details, who enrolled, edit/cancel, and attendance.
class TrainingAdminPage extends StatelessWidget {
  final String id;
  const TrainingAdminPage({super.key, required this.id});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => TrainingAdminViewModel(id, salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), field: c.read<FieldRepository>()),
    child: const _AdminBody(),
  );
}

class _AdminBody extends StatelessWidget {
  const _AdminBody();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TrainingAdminViewModel>();
    final t = vm.training;
    if (t == null) {
      return HPage(
        title: tr('Training'),
        children: [EmptyState(icon: 'grad', title: tr('Session not found'), text: tr('It may have been removed.'))],
      );
    }
    final c = context.c;
    final scheduled = t.status == 'SCHEDULED';
    final marking = scheduled && vm.started;
    if (marking) vm.seedAttendance();

    // On HOLA, only trainers may run a session: follow its allowedActions.
    final canRun = !t.onServer || t.allowed.any({'edit', 'cancel', 'complete', 'attendance'}.contains);
    final Widget? footer = !scheduled || !canRun
        ? null
        : marking
        ? HButton(
            tr('Close session · {n} attended', {'n': vm.attended.length}),
            icon: 'check',
            block: true,
            kind: BtnKind.ok,
            onTap: () async {
              if (await confirmSheet(
                context,
                title: tr('Close this session?'),
                body: tr('{people} will be marked as attended and notified.', {'people': plural(vm.attended.length, 'person', 'people')}),
                confirm: tr('Close session'),
              )) {
                await attempt(vm.complete, success: tr('Attendance saved'), icon: 'grad');
              }
            },
          )
        : Row(
            children: [
              Expanded(
                child: HButton(
                  tr('Cancel'),
                  kind: BtnKind.dangerSoft,
                  onTap: () async {
                    if (await confirmSheet(
                      context,
                      title: tr('Cancel {title}?', {'title': t.title}),
                      body: t.enrolled.isEmpty ? null : tr('{people} enrolled will be notified.', {'people': plural(t.enrolled.length, 'person', 'people')}),
                      confirm: tr('Cancel session'),
                      danger: true,
                      cancel: tr('Keep it'),
                    )) {
                      await attempt(vm.cancel, success: tr('Session cancelled'), icon: 'x');
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: HButton(
                  tr('Edit'),
                  icon: 'edit',
                  kind: BtnKind.secondary,
                  onTap: () => pushPage(context, TrainingEditorPage(existing: t)),
                ),
              ),
            ],
          );

    return HPage(
      title: t.title,
      footer: footer,
      children: staggered([
        HCard(
          gradient: scheduled ? G.btn : null,
          child: VStack(gap: 6, [
            Text(t.title, style: T.h2(context).copyWith(color: scheduled ? Colors.white : null)),
            Text(
              '${dLabel(t.at)} · ${fmtTime(t.at)} – ${fmtTime(t.at.add(Duration(minutes: t.durationMin)))}',
              style: T.sm(context).copyWith(color: scheduled ? Colors.white.withValues(alpha: .9) : null),
            ),
            Text(t.location, style: T.sm(context).copyWith(color: scheduled ? Colors.white.withValues(alpha: .9) : null)),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft, child: StatusBadge(t.status)),
          ]),
        ),
        if (t.description.isNotEmpty) ...[const SizedBox(height: 14), Text(t.description, style: T.body(context))],
        const SizedBox(height: 24),
        KpiStrip([
          Kpi(tr('Enrolled'), t.booked, hl: true, icon: 'users'),
          Kpi(tr('Seats left'), t.seatsLeft < 0 ? 0 : t.seatsLeft, icon: 'grad'),
          if (t.status == 'COMPLETED') Kpi(tr('Attended'), t.attended.length, icon: 'check'),
        ]),
        const SizedBox(height: 22),
        SecHead(marking ? tr('Who attended?') : tr('Enrolled')),
        const SizedBox(height: 12),
        if (t.enrolled.isEmpty)
          HCard(
            child: Text(
              scheduled ? tr('No one has enrolled yet. Salon owners and staff were notified and can enrol from their app.') : tr('No one enrolled.'),
              style: T.sm(context).copyWith(color: c.muted),
            ),
          )
        else
          CardList([
            for (final p in t.enrolled)
              Tap(
                onTap: marking ? () => vm.toggle(p) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Avatar(vm.personName(p), size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(vm.personName(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                            if (vm.salonOf(p).isNotEmpty) Text(vm.salonOf(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context)),
                          ],
                        ),
                      ),
                      if (marking)
                        HIcon(vm.attended.contains(p) ? 'check' : 'x', size: 20, color: vm.attended.contains(p) ? c.ok : c.subtle)
                      else if (t.status == 'COMPLETED')
                        ToneBadge(t.attended.contains(p) ? tr('Attended') : tr('Absent'), tone: t.attended.contains(p) ? 'ok' : 'mute'),
                    ],
                  ),
                ),
              ),
          ]),
        if (marking)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('Tap a person to mark them absent or present.'), style: T.cap(context)),
          ),
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// A HOLA trainer's home: their sessions, upcoming first, and "New session".
class TrainerHome extends StatelessWidget {
  const TrainerHome({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => TrainingsViewModel(salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>(), field: c.read<FieldRepository>()),
    child: Builder(
      builder: (context) {
        final vm = context.watch<TrainingsViewModel>();
        final me = context.read<AuthRepository>().current;
        return BandView(
          role: 'field',
          onRefresh: context.read<FieldRepository>().syncTrainings,
          children: [
            ...staggered([
              TopHead(
                eyebrow: tr('HOLA Academy'),
                title: tr('{greeting}, {name}', {
                  'greeting': now().hour < 12
                      ? tr('Good morning')
                      : now().hour < 17
                      ? tr('Good afternoon')
                      : tr('Good evening'),
                  'name': me?.firstName ?? '',
                }),
                oneLine: true,
                actions: const [NotificationBell()],
              ),
              const SizedBox(height: 22),
            ]),
            BandMark(
              match: true,
              child: Reveal(
                i: 1,
                child: KpiRow([
                  Kpi(tr('Upcoming'), vm.upcoming.length, hl: true),
                  Kpi(tr('Booked'), vm.upcoming.fold(0, (n, t) => n + t.booked)),
                  Kpi(tr('Completed'), vm.past.where((t) => t.status == 'COMPLETED').length),
                ]),
              ),
            ),
            ...staggered([
              const SizedBox(height: 20),
              HButton(tr('New session'), icon: 'plus', block: true, onTap: () => pushPage(context, const TrainingEditorPage())),
              const SizedBox(height: 24),
              SecHead(tr('Upcoming')),
              const SizedBox(height: 12),
              if (vm.upcoming.isEmpty)
                HCard(
                  child: EmptyState(icon: 'grad', title: tr('Nothing scheduled'), text: tr('Create a session. Salons are notified and can enrol their team.')),
                )
              else
                for (final t in vm.upcoming) Padding(padding: const EdgeInsets.only(bottom: 10), child: TrainingCard(t)),
              if (vm.past.isNotEmpty) ...[
                const SizedBox(height: 14),
                SecHead(tr('Past')),
                const SizedBox(height: 12),
                for (final t in vm.past) Padding(padding: const EdgeInsets.only(bottom: 10), child: TrainingCard(t)),
              ],
              const SizedBox(height: 24),
            ], 2),
          ],
        );
      },
    ),
  );
}

/// Trainer's More tab: account, app settings, sign out.
class TrainerMore extends StatelessWidget {
  const TrainerMore({super.key});
  @override
  Widget build(BuildContext context) => BandView(
    role: 'field',
    children: [
      ...staggered([TopHead(title: tr('More')), const SizedBox(height: 16), AccountCard()]),
      const BandMark(),
      ...staggered([const SizedBox(height: 24), AppSettingsGroup(), const SizedBox(height: 24), SignOutButton()], 3),
    ],
  );
}
