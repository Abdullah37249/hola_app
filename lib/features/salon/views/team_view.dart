import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';

/// Owner's team: who works today, leave to answer, add and manage people.
class SalonTeam extends StatelessWidget {
  const SalonTeam({super.key});
  @override
  Widget build(BuildContext context) => const SalonScope(child: _Team());
}

class _Team extends StatelessWidget {
  const _Team();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final team = vm.team;
    final pending = vm.pendingLeave;
    final c = context.c;
    // Day range for the shift bars: the salon's opening hours today, else 8–22.
    final open = vm.branches.map((b) => b.hoursOn(today)).whereType<Shift>();
    final d0 = open.isEmpty ? 8 * 60 : open.map((s) => s.start).reduce((a, b) => a < b ? a : b);
    final d1 = open.isEmpty ? 22 * 60 : open.map((s) => s.end).reduce((a, b) => a > b ? a : b);
    return BandView(
      role: 'salon',
      children: [
        ...staggered([
          TopHead(
            title: tr('Team'),
            sub: '${plural(team.length, 'person', 'people')} · ${tr('{n} taking bookings', {'n': vm.bookable.length})}',
            actions: [HButton(tr('Add'), icon: 'plus', kind: BtnKind.white, small: true, onTap: () => _addSheet(context, vm))],
          ),
        ]),
        const SizedBox(height: 18), // clear the curve under the subtitle
        const BandMark(),
        const SizedBox(height: 24),
        if (pending.isNotEmpty) ...[
          Reveal(i: 2, child: SecHead(tr('Leave requests'))),
          const SizedBox(height: 12),
          for (final l in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Reveal(i: 3, child: LeaveCard(l, vm: vm, decide: true)),
            ),
          const SizedBox(height: 16),
        ],
        Reveal(i: 4, child: SecHead(tr("Today's hours"), action: open.isEmpty ? null : '${fmtMin(d0)} – ${fmtMin(d1)}')),
        const SizedBox(height: 12),
        Reveal(
          i: 5,
          child: Group(
            children: [
              for (final p in team)
                InkWell(
                  onTap: () => pushPage(context, MemberPage(id: p.accountId)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Avatar(vm.nameOf(p.accountId), size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(vm.nameOf(p.accountId), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                              Text(
                                [
                                  p.title,
                                  if (!p.bookable) tr('not taking bookings'),
                                  vm.onLeave(p.accountId, today) ? tr('on leave today') : shiftText(p.shiftOn(today)),
                                ].where((s) => s.isNotEmpty).join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: T.cap(context),
                              ),
                              const SizedBox(height: 6),
                              ShiftBar(shift: vm.onLeave(p.accountId, today) ? null : p.shiftOn(today), dayStart: d0, dayEnd: d1),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        HIcon('chev', size: 18, color: c.subtle),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (team.length == 1) ...[
          const SizedBox(height: 16),
          Reveal(
            i: 6,
            child: HCard(
              child: EmptyState(
                icon: 'users',
                title: tr('Add your stylists'),
                text: tr('Clients can book them by name, and each gets their own day on HOLA.'),
                cta: HButton(tr('Add team member'), icon: 'plus', kind: BtnKind.secondary, small: true, onTap: () => _addSheet(context, vm)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Reveal(
          i: 7,
          child: Group(
            children: [
              MRow(
                icon: 'cal',
                title: tr('Leave requests'),
                sub: pending.isEmpty ? tr('Approved and past time off') : tr('{n} waiting for you', {'n': pending.length}),
                trailing: countOrChev(context, pending.length, warn: true),
                onTap: () => pushPage(context, const LeaveRequestsPage()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _addSheet(BuildContext context, SalonViewModel vm) => showHSheet(context, (ctx) => _AddMember(vm: vm));
}

class _AddMember extends StatefulWidget {
  final SalonViewModel vm;
  const _AddMember({required this.vm});
  @override
  State<_AddMember> createState() => _AddMemberState();
}

class _AddMemberState extends State<_AddMember> {
  final name = TextEditingController(), email = TextEditingController(), phone = TextEditingController(), pass = TextEditingController(), title = TextEditingController();
  final errors = FieldErrors();

  @override
  void dispose() {
    for (final t in [name, email, phone, pass, title]) {
      t.dispose();
    }
    errors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VStack(gap: 14, [
    SheetHead(tr('Add a team member'), sub: tr('They sign in to HOLA with this email and password to see their own appointments.')),
    HField(label: tr('Full name'), hint: tr('e.g. Ayesha Malik'), icon: 'user', controller: name, caps: TextCapitalization.words, name: 'name', errors: errors),
    HField(label: tr('Role'), hint: tr('e.g. Senior stylist'), icon: 'scissors', controller: title, caps: TextCapitalization.sentences),
    HField(label: tr('Email'), hint: 'name@example.com', icon: 'mail', controller: email, keyboard: TextInputType.emailAddress, name: 'email', errors: errors),
    HField(label: tr('Phone'), hint: '0300 1234567', icon: 'phone', controller: phone, keyboard: TextInputType.phone, name: 'phone', errors: errors),
    HField(label: tr('Temporary password'), hint: tr('At least 8 characters'), icon: 'shield', controller: pass, keyboard: TextInputType.visiblePassword, action: TextInputAction.done, helper: tr('Share it with them; they can change it in their profile.'), name: 'password', errors: errors),
    HButton(
      tr('Add to team'),
      icon: 'plus',
      block: true,
      onTap: () async {
        final ok = await attempt(
          () => widget.vm.addStaff(name: name.text, email: email.text, phone: phone.text, password: pass.text, title: title.text),
          success: tr('{name} added to your team', {'name': name.text.trim().split(' ').first}),
          errors: errors,
        );
        if (!ok || !context.mounted) return;
        final creds = '${tr('HOLA sign-in')}\n${tr('Email')}: ${email.text.trim().toLowerCase()}\n${tr('Password')}: ${pass.text}';
        Navigator.pop(context);
        final root = Navigator.of(context, rootNavigator: true).context;
        if (!root.mounted) return;
        showHSheet(
          root,
          (ctx) => VStack(gap: 14, [
            SheetHead(tr('Share their sign-in'), sub: tr('Send these details to your team member. Set their working hours next.')),
            HCard(
              color: ctx.c.surface2,
              child: SelectableText(creds, style: T.body(ctx)),
            ),
            HButton(
              tr('Copy details'),
              icon: 'clip',
              block: true,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: creds));
                if (ctx.mounted) Navigator.pop(ctx);
                Fx.toast(tr('Sign-in details copied'));
              },
            ),
          ]),
        );
      },
    ),
  ]);
}

/// One team member: role, whether they take bookings, weekly hours.
class MemberPage extends StatelessWidget {
  final String id;
  const MemberPage({super.key, required this.id});
  @override
  Widget build(BuildContext context) => SalonScope(child: _Member(id));
}

class _Member extends StatefulWidget {
  final String id;
  const _Member(this.id);
  @override
  State<_Member> createState() => _MemberState();
}

class _MemberState extends State<_Member> {
  late final SalonViewModel vm = context.read<SalonViewModel>();
  late final StaffProfile? p = vm.profile(widget.id);
  late final title = TextEditingController(text: p?.title ?? '');
  late bool bookable = p?.bookable ?? true;
  late List<Shift?> week = [...?p?.week];

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final person = vm.person(widget.id);
    if (p == null || person == null) {
      return HPage(
        title: tr('Team member'),
        children: [EmptyState(icon: 'users', title: tr('Not on the team'), text: tr('This person was removed.'))],
      );
    }
    final isOwner = widget.id == vm.salon?.ownerId;
    final upcoming = vm.all.where((a) => a.staffId == widget.id && a.startsAt.isAfter(now()) && ApptStatus.holding.contains(a.status)).length;
    final leave = vm.leave.where((l) => l.staffId == widget.id && l.status != 'CANCELLED').toList();
    return HPage(
      title: person.name,
      footer: vm.isOwner
          ? FootBar(
              child: HButton(
                tr('Save changes'),
                block: true,
                onTap: () async {
                  final ok = await attempt(
                    () => vm.updateStaff(widget.id, title: title.text, bookable: bookable, week: week),
                    success: tr('Saved'),
                  );
                  if (ok && context.mounted) popPage(context);
                },
              ),
            )
          : null,
      children: [
        const SizedBox(height: 8),
        ...staggered([
          Row(
            children: [
              Avatar(person.name, size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(person.name, style: T.h2(context)),
                    Text(person.email, style: T.sub(context)),
                    if (person.phone.isNotEmpty) Text(person.phone, style: T.sub(context)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          KpiRow([Kpi(tr('Upcoming bookings'), upcoming), Kpi(tr('Leave days'), leave.where((l) => l.status == 'APPROVED').fold(0, (t, l) => t + l.to.difference(l.from).inDays + 1))]),
          const SizedBox(height: 16),
          HField(label: tr('Role'), hint: tr('e.g. Senior stylist'), controller: title),
          const SizedBox(height: 12),
          Group(
            children: [
              SettingRow(
                title: tr('Takes bookings'),
                sub: tr('Clients can pick them and walk-ins can be added'),
                control: HSwitch(on: bookable, onChanged: (v) => setState(() => bookable = v)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SecHead(tr('Weekly hours')),
          const SizedBox(height: 4),
          Text(tr('Clients can only book inside these hours (and the salon’s opening hours).'), style: T.cap(context)),
          const SizedBox(height: 12),
          WeekEditor(week: week, onChanged: (w) => setState(() => week = w)),
          if (!isOwner && vm.isOwner) ...[
            const SizedBox(height: 20),
            HButton(
              tr('Remove from team'),
              icon: 'x',
              kind: BtnKind.dangerSoft,
              block: true,
              onTap: () async {
                if (!await confirmSheet(context, title: tr('Remove {name}?', {'name': person.firstName}), body: tr('Their HOLA sign-in stops working. Past appointments keep their name.'), confirm: tr('Remove'), danger: true)) {
                  return;
                }
                final ok = await attempt(() => vm.removeStaff(widget.id), success: tr('{name} removed', {'name': person.firstName}));
                if (ok && context.mounted) popPage(context);
              },
            ),
          ],
        ]),
      ],
    );
  }
}

/// A leave request card; owners can approve or decline pending ones.
class LeaveCard extends StatelessWidget {
  final LeaveRequest l;
  final SalonViewModel vm;
  final bool decide, mine;
  const LeaveCard(this.l, {super.key, required this.vm, this.decide = false, this.mine = false});
  @override
  Widget build(BuildContext context) {
    final days = l.to.difference(l.from).inDays + 1;
    return HCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine) ...[Avatar(vm.nameOf(l.staffId), size: 40), const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mine ? (days == 1 ? dLabel(l.from) : '${dLabel(l.from)} – ${dLabel(l.to)}') : vm.nameOf(l.staffId), style: T.ttl(context)),
                    Text(
                      mine ? '${plural(days, 'day')} · ${l.reason}' : '${days == 1 ? dLabel(l.from) : '${dLabel(l.from)} – ${dLabel(l.to)}'} · ${l.reason}',
                      style: T.sm(context).copyWith(color: context.c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                l.status,
                label: switch (l.status) {
                  'APPROVED' => tr('Approved'),
                  'DECLINED' => tr('Declined'),
                  'CANCELLED' => tr('Withdrawn'),
                  _ => tr('Pending'),
                },
              ),
            ],
          ),
          if (decide && l.status == 'PENDING') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: HButton(
                    tr('Decline'),
                    kind: BtnKind.secondary,
                    small: true,
                    onTap: () => attempt(() => vm.decideLeave(l.id, false), success: tr('Leave declined'), icon: 'x'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HButton(tr('Approve'), small: true, onTap: () => attempt(() => vm.decideLeave(l.id, true), success: tr('Leave approved'))),
                ),
              ],
            ),
          ],
          if (mine && l.status == 'PENDING') ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: HButton(
                tr('Withdraw'),
                kind: BtnKind.ghost,
                small: true,
                onTap: () => attempt(() => vm.withdrawLeave(l.id), success: tr('Request withdrawn')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Owner: every leave request, pending first.
class LeaveRequestsPage extends StatelessWidget {
  const LeaveRequestsPage({super.key});
  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        final all = [...vm.pendingLeave, ...vm.leave.where((l) => l.status != 'PENDING').toList().reversed];
        return HPage(
          title: tr('Leave requests'),
          children: [
            const SizedBox(height: 8),
            if (all.isEmpty)
              HCard(
                child: EmptyState(icon: 'cal', title: tr('No leave requests'), text: tr('When your team asks for time off, you approve or decline it here.')),
              ),
            for (final (i, l) in all.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Reveal(
                  i: i,
                  child: LeaveCard(l, vm: vm, decide: vm.isOwner),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// The signed-in team member's own hours and leave.
class MyLeavePage extends StatelessWidget {
  const MyLeavePage({super.key});
  @override
  Widget build(BuildContext context) => SalonScope(
    child: Builder(
      builder: (context) {
        final vm = context.watch<SalonViewModel>();
        final me = vm.me;
        final p = me == null ? null : vm.profile(me.id);
        final mine = vm.myLeave();
        return HPage(
          title: tr('My schedule & leave'),
          footer: FootBar(
            child: HButton(
              tr('Request leave'),
              icon: 'plus',
              block: true,
              onTap: () => showHSheet(context, (ctx) => _LeaveForm(vm: vm)),
            ),
          ),
          children: [
            const SizedBox(height: 8),
            ...staggered([
              SecHead(tr('My weekly hours')),
              const SizedBox(height: 12),
              Group(
                children: [
                  for (var i = 0; i < 7; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(child: Text(tr(WeekEditor.names[i]), style: T.ttl(context))),
                          Text(shiftText(p?.week[i]), style: T.sm(context).copyWith(color: p?.week[i] == null ? context.c.muted : context.c.ink)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(vm.isOwner ? tr('Change hours in Team.') : tr('Your salon owner sets these hours.'), style: T.cap(context)),
              const SizedBox(height: 22),
              SecHead(tr('Leave')),
              const SizedBox(height: 12),
              if (mine.isEmpty)
                HCard(
                  child: EmptyState(icon: 'sun', title: tr('No leave yet'), text: tr('Request days off and your salon owner will approve them. You won’t be booked on approved days.')),
                ),
              for (final l in mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LeaveCard(l, vm: vm, mine: true),
                ),
            ]),
          ],
        );
      },
    ),
  );
}

class _LeaveForm extends StatefulWidget {
  final SalonViewModel vm;
  const _LeaveForm({required this.vm});
  @override
  State<_LeaveForm> createState() => _LeaveFormState();
}

class _LeaveFormState extends State<_LeaveForm> {
  DateTime? from, to;
  final reason = TextEditingController();

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial, DateTime first) => showDatePicker(context: context, initialDate: initial ?? first, firstDate: first, lastDate: addDays(today, 365));

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget dateBox(String label, DateTime? d, VoidCallback onTap) => Expanded(
      child: Tap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: T.cap(context)),
              Text(d == null ? tr('Pick a date') : dLabel(d), style: T.ttl(context).copyWith(color: d == null ? c.subtle : c.ink)),
            ],
          ),
        ),
      ),
    );
    return VStack(gap: 14, [
      SheetHead(tr('Request leave'), sub: tr('Your salon owner is notified and approves it.')),
      Row(
        children: [
          dateBox(tr('First day'), from, () async {
            final d = await _pick(from, today);
            if (d == null) return;
            setState(() {
              from = d;
              if (to == null || to!.isBefore(d)) to = d;
            });
          }),
          const SizedBox(width: 10),
          dateBox(tr('Last day'), to, () async {
            final d = await _pick(to ?? from, from ?? today);
            if (d != null) setState(() => to = d);
          }),
        ],
      ),
      HField(label: tr('Reason'), hint: tr('e.g. Family wedding'), controller: reason, onChanged: (_) => setState(() {})),
      HButton(
        tr('Send request'),
        block: true,
        onTap: from == null || to == null || reason.text.trim().length < 3
            ? null
            : () async {
                final ok = await attempt(() => widget.vm.requestLeave(from!, to!, reason.text), success: widget.vm.isOwner ? tr('Leave added') : tr('Request sent'));
                if (ok && context.mounted) Navigator.pop(context);
              },
      ),
    ]);
  }
}
