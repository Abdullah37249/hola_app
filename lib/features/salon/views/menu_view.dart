import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/salon_widgets.dart';

/// Owner's service menu: what clients can book, at what price and length.
class SalonMenu extends StatelessWidget {
  const SalonMenu({super.key});
  @override
  Widget build(BuildContext context) => const SalonScope(child: _Menu());
}

class _Menu extends StatelessWidget {
  const _Menu();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final svcs = vm.services;
    return BandView(role: 'salon', children: [
      ...staggered([
        TopHead(title: tr('Service menu'), sub: svcs.isEmpty ? tr('What clients can book') : tr('{n} of {total} visible to clients', {'n': vm.activeServices.length, 'total': svcs.length}), actions: [
          HButton(tr('Add'), icon: 'plus', kind: BtnKind.white, small: true, onTap: () => showServiceSheet(context, vm)),
        ]),
        const SizedBox(height: 20),
      ]),
      if (svcs.isEmpty)
        Reveal(
          i: 2,
          child: HCard(
            child: EmptyState(
              icon: 'scissors',
              title: tr('Add your first service'),
              text: tr('Clients book services from this menu. Add each one with its price and how long it takes.'),
              cta: HButton(tr('Add a service'), icon: 'plus', small: true, onTap: () => showServiceSheet(context, vm)),
            ),
          ),
        )
      else
        ...ServiceList(vm: vm, editable: true).sections(context),
    ]);
  }
}

/// Services grouped by category; owners can edit and hide, staff only read.
class ServiceList {
  final SalonViewModel vm;
  final bool editable;
  const ServiceList({required this.vm, required this.editable});

  List<Widget> sections(BuildContext context) {
    final c = context.c;
    final svcs = vm.services.where((s) => editable || s.active).toList();
    final out = <Widget>[];
    var i = 2;
    for (final cat in serviceCategories) {
      final xs = svcs.where((s) => s.category == cat).toList();
      if (xs.isEmpty) continue;
      out.add(Reveal(i: i++, child: Padding(padding: EdgeInsets.only(bottom: 10, top: out.isEmpty ? 0 : 18), child: Text(L10n.ur ? tr(cat) : cat.toUpperCase(), style: T.eyebrow(context).copyWith(color: editable && out.isEmpty ? Colors.white.withValues(alpha: .85) : null)))));
      out.add(Reveal(
        i: i++,
        child: Group(children: [
          for (final s in xs)
            InkWell(
              onTap: editable ? () => showServiceSheet(context, vm, existing: s) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: HIcon(_icon(cat), size: 20, color: c.brandText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Opacity(
                      opacity: s.active ? 1 : .5,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.name, style: T.ttl(context)),
                        Text('${rs(s.price)} · ${fmtDur(s.durationMin)}${s.active ? '' : ' · ${tr('hidden')}'}', style: T.sm(context).copyWith(color: c.muted)),
                        if (s.description.isNotEmpty) Text(s.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.cap(context)),
                      ]),
                    ),
                  ),
                  if (editable) ...[
                    const SizedBox(width: 8),
                    HSwitch(on: s.active, onChanged: (v) => attempt(() => vm.setServiceActive(s.id, v), success: v ? tr('{name} is visible to clients', {'name': s.name}) : tr('{name} hidden', {'name': s.name}), icon: v ? 'check' : 'x')),
                  ],
                ]),
              ),
            ),
        ]),
      ));
      out.add(const SizedBox(height: 14));
    }
    return out;
  }

  static String _icon(String cat) => switch (cat) { 'Nails' => 'hand', 'Skin' => 'drop', 'Colour' => 'color', 'Spa' => 'layers', 'Bridal' => 'sparkle', 'Makeup' => 'sparkle', _ => 'scissors' };
}

/// Add or edit a service.
Future<void> showServiceSheet(BuildContext context, SalonViewModel vm, {ServiceItem? existing}) => showHSheet(context, (ctx) => _ServiceForm(vm: vm, s: existing));

class _ServiceForm extends StatefulWidget {
  final SalonViewModel vm;
  final ServiceItem? s;
  const _ServiceForm({required this.vm, this.s});
  @override
  State<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<_ServiceForm> {
  late final name = TextEditingController(text: widget.s?.name ?? ''), desc = TextEditingController(text: widget.s?.description ?? ''), price = TextEditingController(text: widget.s == null ? '' : '${widget.s!.price}');
  late String cat = widget.s?.category ?? serviceCategories.first;
  late int dur = widget.s?.durationMin ?? 60;
  late bool active = widget.s?.active ?? true;
  final errors = FieldErrors();

  @override
  void dispose() {
    name.dispose();
    desc.dispose();
    price.dispose();
    errors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.s != null;
    return VStack(gap: 14, [
      SheetHead(editing ? tr('Edit service') : tr('Add a service'), sub: editing ? null : tr('Clients see the name, price and duration when they book.')),
      HField(label: tr('Name'), hint: tr('e.g. Cut & blow-dry'), controller: name, caps: TextCapitalization.sentences, name: 'name', errors: errors),
      Text(tr('Category'), style: HField.labelStyle(context)),
      Wrap(spacing: 8, runSpacing: 8, children: [for (final c in serviceCategories) HChip(tr(c), on: cat == c, onTap: () => setState(() => cat = c))]),
      HField(label: tr('Price (Rs)'), hint: tr('e.g. 3500'), controller: price, keyboard: TextInputType.number, action: TextInputAction.done, name: 'price', errors: errors),
      Row(children: [
        Expanded(child: Text(tr('Duration'), style: HField.labelStyle(context))),
        ValueStepper(value: dur, min: 5, max: 600, step: dur < 60 ? 5 : 15, format: fmtDur, onChanged: (v) => setState(() => dur = v)),
      ]),
      HField(label: tr('Description (optional)'), hint: tr('What’s included'), controller: desc, multiline: true),
      if (editing) Group(children: [SettingRow(title: tr('Visible to clients'), control: HSwitch(on: active, onChanged: (v) => setState(() => active = v)))]),
      HButton(editing ? tr('Save changes') : tr('Add service'), block: true, onTap: () async {
        final p = int.tryParse(price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final ok = await attempt(
          () => widget.vm.saveService(id: widget.s?.id, name: name.text, category: cat, description: desc.text, price: p, durationMin: dur, active: active),
          success: editing ? tr('Saved') : tr('{name} added to your menu', {'name': name.text.trim()}),
          errors: errors,
        );
        if (ok && context.mounted) Navigator.pop(context);
      }),
      if (editing)
        HButton(tr('Delete service'), kind: BtnKind.ghost, block: true, onTap: () async {
          if (!await confirmSheet(context, title: tr('Delete {name}?', {'name': widget.s!.name}), body: tr('Past bookings keep it. If clients have upcoming bookings for it, hide it instead.'), confirm: tr('Delete'), danger: true)) return;
          final ok = await attempt(() => widget.vm.deleteService(widget.s!.id), success: tr('Service deleted'), icon: 'x');
          if (ok && context.mounted) Navigator.pop(context);
        }),
    ]);
  }
}

/// Read-only menu for staff.
class ServiceMenuPage extends StatelessWidget {
  const ServiceMenuPage({super.key});
  @override
  Widget build(BuildContext context) => SalonScope(
        child: Builder(builder: (context) {
          final vm = context.watch<SalonViewModel>();
          return HPage(title: tr('Service menu'), children: [
            const SizedBox(height: 8),
            if (vm.activeServices.isEmpty) EmptyState(icon: 'scissors', title: tr('No services yet'), text: tr('Your salon owner adds services and prices.')),
            ...ServiceList(vm: vm, editable: false).sections(context),
          ]);
        }),
      );
}
