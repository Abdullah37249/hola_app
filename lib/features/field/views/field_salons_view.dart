import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/field_view_models.dart';
import '../widgets/field_widgets.dart';
import 'salon_record_view.dart';

class FieldSalons extends StatelessWidget {
  const FieldSalons({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => FieldSalonsViewModel(salons: c.read<SalonRepository>(), auth: c.read<AuthRepository>()),
    child: const _Body(),
  );
}

class _Body extends StatelessWidget {
  const _Body();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FieldSalonsViewModel>();
    final c = context.c;
    final list = vm.results;
    return BandView(
      role: 'field',
      children: [
        ...staggered([
          TopHead(
            title: tr('Salons'),
            sub: vm.all.isEmpty ? tr('Salons that sign up appear here') : tr('{n} on HOLA · {pending} to verify', {'n': vm.all.length, 'pending': vm.count('PENDING_VERIFICATION')}),
          ),
          const SizedBox(height: 14),
          if (vm.all.isNotEmpty) ...[
            HField(hint: tr('Search by salon, area or owner'), icon: 'search', onChanged: vm.setQuery),
            const SizedBox(height: 12),
            ChipRow(
              children: [
                for (final f in FieldSalonsViewModel.filters)
                  HChip('${f.$2}${vm.count(f.$1) > 0 && f.$1 != 'all' ? ' · ${vm.count(f.$1)}' : ''}', on: vm.filter == f.$1, onTap: () => vm.setFilter(f.$1)),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ]),
        if (vm.all.isEmpty)
          HCard(
            child: EmptyState(icon: 'store', title: tr('No salons have signed up yet'), text: tr('When a salon owner creates their salon in the HOLA app, it lands here for you to verify.')),
          )
        else if (list.isEmpty)
          EmptyState(
            icon: 'search',
            title: tr('Nothing matches'),
            text: tr('Try another search or filter.'),
            cta: HButton(
              tr('Show all salons'),
              small: true,
              kind: BtnKind.secondary,
              onTap: () {
                vm.setFilter('all');
              },
            ),
          )
        else
          ...staggered([
            for (final s in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SalonTile(
                  salon: s,
                  place: vm.place(s.id),
                  owner: vm.owner(s.id)?.name ?? '',
                  services: vm.servicesCount(s.id),
                  onTap: () => pushPage(context, SalonRecordPage(id: s.id)),
                ),
              ),
          ], 3),
        if (list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('Showing {n} of {total}', {'n': list.length, 'total': vm.all.length}),
              textAlign: TextAlign.center,
              style: T.cap(context).copyWith(color: c.subtle),
            ),
          ),
      ],
    );
  }
}
