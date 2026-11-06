import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/customer_lookups.dart';
import '../viewmodels/discover_view_models.dart';
import '../widgets/salon_cards.dart';
import '../widgets/salon_map.dart';

class CustomerExplore extends StatelessWidget {
  const CustomerExplore({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => ExploreViewModel(c.read<SalonRepository>(), c.read<AuthRepository>()), child: const _ExploreBody());
}

class _ExploreBody extends StatefulWidget {
  const _ExploreBody();
  @override
  State<_ExploreBody> createState() => _ExploreBodyState();
}

class _ExploreBodyState extends State<_ExploreBody> {
  final _q = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    exploreIntent.addListener(_maybeFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFocus());
  }

  void _maybeFocus() {
    if (!exploreIntent.focusSearch || !mounted) return;
    exploreIntent.focusSearch = false;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    exploreIntent.removeListener(_maybeFocus);
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ExploreViewModel>();
    final c = context.c;
    // Rebuild when the tab becomes visible so a pending focus request is honoured.
    context.select<SessionViewModel, String?>((s) => s.tab);
    final list = vm.results;
    final cities = vm.cities;
    return BandView(
      role: 'customer',
      onRefresh: vm.syncSalons,
      children: [
        ...staggered([
          TopHead(
            title: tr('Explore'),
            sub: tr('Find and book salons near you'),
            // List ↔ map.
            actions: [IconBtn(vm.showMap ? 'list' : 'map', onBand: true, onTap: vm.toggleMap)],
          ),
          const SizedBox(height: 14),
        ]),
        // Search across the header's edge, like every other screen.
        BandMark(
          match: true,
          child: Reveal(
            i: 1,
            child: TextField(
              controller: _q,
              focusNode: _focus,
              onChanged: vm.setQuery,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontFamily: T.f, fontSize: 16, color: c.ink),
              decoration: InputDecoration(
                hintText: tr('Salon, service or area'),
                hintStyle: TextStyle(color: c.subtle),
                filled: true,
                fillColor: c.surface,
                prefixIcon: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
                  child: HIcon('search', size: 20, color: c.muted),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0),
                suffixIcon: vm.query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _q.clear();
                          vm.setQuery('');
                        },
                        icon: HIcon('x', size: 18, color: c.muted),
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.brand, width: 1.5),
                ),
              ),
            ),
          ),
        ),
        ...staggered([
          const SizedBox(height: 14),
          ChipRow(
            children: [
              HChip(
                vm.locating ? tr('Finding you…') : tr('Near me'),
                icon: 'nav',
                on: vm.nearFirst,
                onTap: vm.locating
                    ? null
                    : () async {
                        if (!await vm.toggleNearMe()) Fx.toast(tr('Turn on location and allow HOLA to use it to see salons near you.'), icon: 'pin', tone: 'bad');
                      },
              ),
              if (cities.length > 1)
                for (final ct in cities) HChip(ct, icon: 'pin', on: vm.city == ct, onTap: () => vm.setCity(ct)),
              for (final cat in serviceCategories) HChip(tr(cat), on: vm.category == cat, onTap: () => vm.setCategory(cat)),
            ],
          ),
        ], 2),
        const SizedBox(height: 20),
        if (list.isEmpty)
          Reveal(
            i: 4,
            child: HCard(
              child: vm.filtered
                  ? EmptyState(
                      icon: 'search',
                      title: tr('No salons match'),
                      text: tr('Try another search or remove a filter.'),
                      cta: HButton(
                        tr('Clear filters'),
                        kind: BtnKind.secondary,
                        small: true,
                        onTap: () {
                          _q.clear();
                          vm.clear();
                        },
                      ),
                    )
                  : EmptyState(icon: 'store', title: tr('No salons yet'), text: tr('Salons appear here as soon as they join HOLA. Check back soon.')),
            ),
          )
        else ...[
          Reveal(
            i: 4,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                [
                  vm.city != null ? tr('{salons} in {city}', {'salons': plural(list.length, 'salon'), 'city': vm.city}) : plural(list.length, 'salon'),
                  if (vm.nearFirst) tr('nearest first'),
                ].join(' · ').toUpperCase(),
                style: T.eyebrow(context),
              ),
            ),
          ),
          if (vm.showMap)
            Reveal(
              i: 5,
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .58,
                child: SalonMap(pins: vm.pins(list), here: vm.here, distanceTo: vm.distanceTo),
              ),
            )
          else
            ...staggered([
              for (final s in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: SalonCard(s, km: vm.distanceTo(s)),
                ),
            ], 5),
        ],
      ],
    );
  }
}
