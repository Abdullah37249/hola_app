import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/gps_capture.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_photos.dart';
import '../widgets/salon_widgets.dart';

/// Owner edits the salon's public details and its branches.
class SalonProfilePage extends StatelessWidget {
  const SalonProfilePage({super.key});
  @override
  Widget build(BuildContext context) => const SalonScope(child: _Profile());
}

class _Profile extends StatefulWidget {
  const _Profile();
  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  late final SalonViewModel vm = context.read<SalonViewModel>();
  late final name = TextEditingController(text: vm.salon?.name ?? ''), phone = TextEditingController(text: vm.salon?.phone ?? ''), about = TextEditingController(text: vm.salon?.about ?? '');
  final errors = FieldErrors();

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    about.dispose();
    errors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final s = vm.salon;
    if (s == null) return HPage(title: tr('Salon profile'), children: const []);
    final c = context.c;
    return HPage(
      title: tr('Salon profile'),
      hero: SalonArt(s.palette, photo: s.cover, height: 160 + MediaQuery.paddingOf(context).top, radius: 0, name: s.name),
      children: [
        const SizedBox(height: 16),
        ...staggered([
          Row(
            children: [
              Expanded(child: Text(s.name, style: T.h1(context))),
              StatusBadge(s.status),
            ],
          ),
          if (s.statusNote != null) ...[const SizedBox(height: 6), Text(s.statusNote!, style: T.sm(context).copyWith(color: c.badInk))],
          const SizedBox(height: 24),
          SecHead(tr('Photos'), action: s.photos.isEmpty ? null : tr('{n} of {max}', {'n': s.photos.length, 'max': maxSalonPhotos})),
          const SizedBox(height: 4),
          Text(
            s.photos.isEmpty ? tr('Salons with photos get chosen more. The first photo is your cover.') : tr('Tap a photo to make it the cover or remove it.'),
            style: T.sm(context).copyWith(color: c.muted),
          ),
          const SizedBox(height: 12),
          SalonPhotos(vm: vm),
          const SizedBox(height: 24),
          SecHead(tr('Details')),
          const SizedBox(height: 12),
          HCard(
            child: VStack(gap: 14, [
              HField(label: tr('Salon name'), controller: name, icon: 'store', caps: TextCapitalization.words, name: 'name', errors: errors),
              HField(label: tr('Phone'), controller: phone, icon: 'phone', keyboard: TextInputType.phone, name: 'phone', errors: errors),
              HField(label: tr('About'), hint: tr('What makes your salon special?'), controller: about, multiline: true),
              HButton(
                tr('Save details'),
                block: true,
                kind: BtnKind.secondary,
                onTap: () => attempt(
                  () => vm.updateSalon(name: name.text, phone: phone.text, about: about.text),
                  success: tr('Salon details saved'),
                  errors: errors,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          SecHead(tr('Branches'), action: tr('Add branch'), onAction: () => _addBranch(context, vm)),
          const SizedBox(height: 12),
          Group(
            children: [
              for (final b in vm.branches)
                MRow(
                  icon: 'pin',
                  title: b.name,
                  sub: '${b.address}, ${b.area}, ${b.city}\n${weekSummary(b.hours)}',
                  onTap: () => pushPage(context, BranchPage(id: b.id)),
                ),
            ],
          ),
        ]),
      ],
    );
  }

  void _addBranch(BuildContext context, SalonViewModel vm) {
    final n = TextEditingController(), a = TextEditingController(), ar = TextEditingController(), ci = TextEditingController(text: vm.branches.firstOrNull?.city ?? '');
    showHSheet(
      context,
      (ctx) => VStack(gap: 14, [
        SheetHead(tr('Add a branch'), sub: tr('Set its opening hours next.')),
        HField(label: tr('Branch name'), hint: tr('e.g. DHA Phase 6'), controller: n),
        HField(label: tr('Street address'), controller: a, icon: 'pin'),
        HField(label: tr('Area'), controller: ar),
        HField(label: tr('City'), controller: ci),
        HButton(
          tr('Add branch'),
          block: true,
          onTap: () async {
            Branch? created;
            final ok = await attempt(
              () async => created = await vm.addBranch(name: n.text, address: a.text, area: ar.text, city: ci.text),
              success: tr('Branch added'),
            );
            if (!ok || !ctx.mounted) return;
            Navigator.pop(ctx);
            if (context.mounted && created != null) pushPage(context, BranchPage(id: created!.id));
          },
        ),
      ]),
    );
  }
}

/// One branch: address and weekly opening hours.
class BranchPage extends StatelessWidget {
  final String id;
  const BranchPage({super.key, required this.id});
  @override
  Widget build(BuildContext context) => SalonScope(child: _Branch(id));
}

class _Branch extends StatefulWidget {
  final String id;
  const _Branch(this.id);
  @override
  State<_Branch> createState() => _BranchState();
}

class _BranchState extends State<_Branch> {
  late final SalonViewModel vm = context.read<SalonViewModel>();
  late final Branch? b = vm.branch(widget.id);
  late final name = TextEditingController(text: b?.name), address = TextEditingController(text: b?.address), area = TextEditingController(text: b?.area), city = TextEditingController(text: b?.city);
  late List<Shift?> hours = [...?b?.hours];
  late GeoFix? gps = b?.location;

  @override
  void dispose() {
    for (final t in [name, address, area, city]) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (b == null) {
      return HPage(
        title: tr('Branch'),
        children: [EmptyState(icon: 'pin', title: tr('Branch not found'), text: tr('It may have been deleted.'))],
      );
    }
    return HPage(
      title: b!.name,
      footer: FootBar(
        child: HButton(
          tr('Save branch'),
          block: true,
          onTap: () async {
            final ok = await attempt(() async {
              await vm.updateBranch(b!.id, name: name.text, address: address.text, area: area.text, city: city.text, hours: hours);
              if (gps != null && gps != b!.location) await vm.setBranchLocation(b!.id, gps!);
            }, success: tr('Branch saved'));
            if (ok && context.mounted) popPage(context);
          },
        ),
      ),
      children: [
        const SizedBox(height: 8),
        ...staggered([
          HCard(
            child: VStack(gap: 14, [
              HField(label: tr('Branch name'), controller: name),
              HField(label: tr('Street address'), controller: address, icon: 'pin'),
              HField(label: tr('Area'), controller: area),
              HField(label: tr('City'), controller: city),
              GpsCapture(value: gps, onChanged: (v) => setState(() => gps = v)),
            ]),
          ),
          const SizedBox(height: 22),
          SecHead(tr('Opening hours')),
          const SizedBox(height: 4),
          Text(tr('Clients can book only while the branch is open and someone is working.'), style: T.cap(context)),
          const SizedBox(height: 12),
          WeekEditor(week: hours, offLabel: tr('Closed'), onChanged: (w) => setState(() => hours = w)),
          if (vm.branches.length > 1) ...[
            const SizedBox(height: 20),
            HButton(
              tr('Delete branch'),
              icon: 'x',
              kind: BtnKind.dangerSoft,
              block: true,
              onTap: () async {
                if (!await confirmSheet(
                  context,
                  title: tr('Delete {name}?', {'name': b!.name}),
                  body: tr('Clients will no longer be able to book this branch.'),
                  confirm: tr('Delete branch'),
                  danger: true,
                )) {
                  return;
                }
                final ok = await attempt(() => vm.deleteBranch(b!.id), success: tr('Branch deleted'), icon: 'x');
                if (ok && context.mounted) popPage(context);
              },
            ),
          ],
        ]),
      ],
    );
  }
}
