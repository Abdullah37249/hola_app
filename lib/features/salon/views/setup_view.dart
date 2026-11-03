import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/sfx.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/gps_capture.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/setup_view_model.dart';

/// First run for a salon owner: create the salon and its first branch.
/// Root swaps to the salon shell as soon as the salon exists.
class SalonSetupPage extends StatelessWidget {
  const SalonSetupPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => SetupViewModel(c.read<SalonRepository>(), c.read<AuthRepository>()), child: const _SetupBody());
}

class _SetupBody extends StatefulWidget {
  const _SetupBody();
  @override
  State<_SetupBody> createState() => _SetupBodyState();
}

class _SetupBodyState extends State<_SetupBody> {
  late final SetupViewModel vm = context.read<SetupViewModel>();
  late final name = TextEditingController(), phone = TextEditingController(text: vm.ownerPhone), about = TextEditingController();
  late final branch = TextEditingController(), address = TextEditingController(), area = TextEditingController(), city = TextEditingController(text: vm.ownerCity);
  final errors = FieldErrors();

  @override
  void initState() {
    super.initState();
    vm.phone = phone.text;
    vm.city = city.text;
  }

  @override
  void dispose() {
    for (final t in [name, phone, about, branch, address, area, city]) {
      t.dispose();
    }
    errors.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    final miss = vm.missing;
    if (miss != null) {
      Sfx.error();
      errors.set(miss.field!, miss.message);
      return;
    }
    FocusScope.of(context).unfocus();
    if (vm.step < SetupViewModel.steps.length - 1) {
      Sfx.nav();
      vm.next();
      return;
    }
    await attempt(vm.create, success: tr('Welcome to HOLA, {name}!', {'name': vm.name.trim()}), confetti: true); // review step: no fields on screen, so errors stay toasts
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SetupViewModel>();
    final c = context.c;
    final top = MediaQuery.paddingOf(context).top;
    final step = vm.step;
    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (did, _) {
        if (!did) vm.back();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.only(bottom: 140 + MediaQuery.paddingOf(context).bottom),
              children: [
                // Header on a band that sizes itself to the copy.
                Stack(
                  children: [
                    const Positioned.fill(
                      child: Band(role: 'salon', height: double.infinity),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(kGutter, top + 12, kGutter, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(tr('SALON SET-UP · STEP {n} OF 3', {'n': step + 1}), style: T.eyebrow(context).copyWith(color: Colors.white.withValues(alpha: .85))),
                              ),
                              TextButton(
                                onPressed: () async {
                                  if (await confirmSheet(context, title: tr('Sign out?'), body: tr('You can finish setting up your salon next time you sign in.'), confirm: tr('Sign out'))) {
                                    await vm.signOut();
                                  }
                                },
                                child: Text(
                                  tr('Sign out'),
                                  style: const TextStyle(fontFamily: T.f, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            step == 0
                                ? tr('Hi {name}, let’s set up your salon', {'name': vm.ownerName})
                                : step == 1
                                ? tr('Where can clients find you?')
                                : tr('Ready to open your doors'),
                            style: T.h1(context).copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            step == 0
                                ? tr('This is what clients see on HOLA. You can change it any time.')
                                : step == 1
                                ? tr('Your first branch. Add more later from Salon profile.')
                                : tr('Check the details. You can change any of them later.'),
                            style: T.sm(context).copyWith(color: Colors.white.withValues(alpha: .9)),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                if (i > 0) const SizedBox(width: 6),
                                Expanded(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    height: 5,
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: i <= step ? Colors.white : Colors.white.withValues(alpha: .3)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kGutter),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(
                      key: ValueKey(step),
                      child: Reveal(child: _stepBody(context, vm)),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FootBar(
                child: Row(
                  children: [
                    if (step > 0) ...[
                      SizedBox(
                        width: 52,
                        child: HButton('', icon: 'back', kind: BtnKind.soft, onTap: vm.back),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: HButton(step == 2 ? tr('Create my salon') : tr('Continue'), block: true, onTap: _next)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context, SetupViewModel vm) {
    final c = context.c;
    switch (vm.step) {
      case 0:
        return HCard(
          child: VStack(gap: 14, [
            HField(label: tr('Salon name'), hint: tr('e.g. Maison Noor'), icon: 'store', controller: name, caps: TextCapitalization.words, onChanged: (v) => vm.name = v, name: 'name', errors: errors),
            HField(label: tr('Salon phone'), hint: '0300 1234567', icon: 'phone', controller: phone, keyboard: TextInputType.phone, onChanged: (v) => vm.phone = v, name: 'phone', errors: errors),
            HField(label: tr('About (optional)'), hint: tr('What makes your salon special?'), controller: about, multiline: true, onChanged: (v) => vm.about = v),
          ]),
        );
      case 1:
        return HCard(
          child: VStack(gap: 14, [
            HField(label: tr('Branch name (optional)'), hint: tr('e.g. Gulberg'), controller: branch, caps: TextCapitalization.words, onChanged: (v) => vm.branchName = v),
            HField(
              label: tr('Street address'),
              hint: tr('e.g. 12-B Main Boulevard'),
              icon: 'pin',
              controller: address,
              caps: TextCapitalization.words,
              autofill: const [AutofillHints.streetAddressLine1],
              onChanged: (v) => vm.address = v,
              name: 'address',
              errors: errors,
            ),
            HField(label: tr('Area'), hint: tr('e.g. Gulberg III'), controller: area, caps: TextCapitalization.words, onChanged: (v) => vm.area = v, name: 'area', errors: errors),
            HField(
              label: tr('City'),
              hint: tr('e.g. Lahore'),
              controller: city,
              caps: TextCapitalization.words,
              autofill: const [AutofillHints.addressCity],
              action: TextInputAction.done,
              onSubmitted: (_) => _next(),
              onChanged: (v) => vm.city = v,
              name: 'city',
              errors: errors,
            ),
            GpsCapture(value: vm.location, onChanged: vm.setLocation),
          ]),
        );
      default:
        Widget line(String icon, String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HIcon(icon, size: 20, color: c.brandText),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k, style: T.cap(context)),
                    Text(v, style: T.ttl(context)),
                  ],
                ),
              ),
            ],
          ),
        );
        return VStack(gap: 14, [
          // How the salon will appear to clients.
          HCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SalonArt(vm.salonCount, height: 120, radius: 0, name: vm.name.trim()),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vm.name.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h2(context)),
                      Text([vm.area.trim(), vm.city.trim()].where((s) => s.isNotEmpty).join(', '), style: T.sub(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          HCard(
            child: Column(
              children: [
                line('store', tr('Salon'), vm.name.trim()),
                line('phone', tr('Phone'), vm.phone.trim()),
                line(
                  'pin',
                  vm.branchName.trim().isEmpty ? tr('First branch') : tr('First branch · {name}', {'name': vm.branchName.trim()}),
                  [vm.address.trim(), vm.area.trim(), vm.city.trim()].where((s) => s.isNotEmpty).join(', '),
                ),
                if (vm.about.trim().isNotEmpty) line('doc', tr('About'), vm.about.trim()),
              ],
            ),
          ),
          HCard(
            color: c.surface2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('What happens next'), style: T.ttl(context)),
                const SizedBox(height: 8),
                for (final (i, t) in [
                  tr('Add your services and prices in Menu. Clients can book you from then on.'),
                  tr('Add your team and their working hours in Team.'),
                  tr('A HOLA sales officer verifies your salon: you get the Verified badge and product ordering.'),
                ].indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(fontFamily: T.f, fontSize: 12, fontWeight: FontWeight.w700, color: c.brandText),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(t, style: T.sm(context))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ]);
    }
  }
}
