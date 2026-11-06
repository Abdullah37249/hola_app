import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/customer_lookups.dart';
import '../views/salon_view.dart';

/// Icon per service category.
const categoryIcons = {'Hair': 'scissors', 'Colour': 'color', 'Nails': 'hand', 'Skin': 'drop', 'Bridal': 'sparkle', 'Barber': 'scissors', 'Spa': 'layers', 'Makeup': 'star'};

/// Small frosted tag drawn over salon art.
class GlassTag extends StatelessWidget {
  final String label;
  const GlassTag(this.label, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .88), borderRadius: BorderRadius.circular(999)),
    child: Text(
      label,
      maxLines: 1,
      style: const TextStyle(fontFamily: T.f, fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1D1D1F)),
    ),
  );
}

/// Rating chip, or "New" when the salon has no reviews yet.
class RatingOrNew extends StatelessWidget {
  final SalonRating r;
  const RatingOrNew(this.r, {super.key});
  @override
  Widget build(BuildContext context) => r.count == 0 ? ToneBadge(tr('New'), tone: 'info') : RatingTag(r.average);
}

/// Open/closed line for a salon's first branch.
class OpenLine extends StatelessWidget {
  final Branch? b;
  const OpenLine(this.b, {super.key});
  @override
  Widget build(BuildContext context) {
    if (b == null) return const SizedBox();
    final o = openState(b!);
    return Text(
      o.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: T.sm(context).copyWith(color: o.open ? context.c.ok : context.c.muted, fontWeight: FontWeight.w600),
    );
  }
}

/// Large salon card: cover, name + rating, one meta line, open state + price.
class SalonCard extends StatelessWidget {
  final Salon s;

  /// How far away it is, when the customer shared their location.
  final double? km;
  const SalonCard(this.s, {super.key, this.km});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final repo = context.read<SalonRepository>();
    final b = repo.branches(s.id).firstOrNull;
    final cats = repo.categoriesOf(s.id);
    final place = b == null ? '' : [b.area, b.city].where((x) => x.isNotEmpty).join(', ');
    return Tap(
      onTap: () => pushPage(context, SalonPage(id: s.id)),
      scale: .985,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: c.lift),
            child: SalonArt(s.palette, photo: s.cover, height: 168, radius: 20, name: s.name),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h3(context)),
              ),
              const SizedBox(width: 8),
              RatingOrNew(repo.rating(s.id)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [if (km != null) kmLabel(km!), place, cats.take(3).join(', ')].where((x) => x.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.sm(context).copyWith(color: c.muted),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(child: OpenLine(b)),
              // No price until the salon has a menu (never "from Rs 0").
              if (repo.fromPrice(s.id) > 0)
                Flexible(
                  child: Text(
                    '  ·  ${tr('from {price}', {'price': rsShort(repo.fromPrice(s.id))})}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.sm(context).copyWith(color: c.ink),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact salon card for horizontal rows.
class SalonMini extends StatelessWidget {
  final Salon s;
  const SalonMini(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<SalonRepository>();
    final b = repo.branches(s.id).firstOrNull;
    final place = b == null ? '' : (b.area.isEmpty ? b.city : b.area);
    return Tap(
      onTap: () => pushPage(context, SalonPage(id: s.id)),
      child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: context.c.lift),
              child: SalonArt(s.palette, photo: s.cover, height: 120, name: s.name),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                ),
                const SizedBox(width: 6),
                RatingOrNew(repo.rating(s.id)),
              ],
            ),
            Text(
              [
                place,
                if (repo.fromPrice(s.id) > 0) tr('from {price}', {'price': rsShort(repo.fromPrice(s.id))}),
              ].where((x) => x.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.sm(context).copyWith(color: context.c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Square salon thumbnail.
Widget artThumb(int p, double size, {double radius = 10, String? name, String? photo}) => SizedBox(
  width: size,
  height: size,
  child: SalonArt(p, n: 2, radius: radius, name: name, photo: photo),
);

/// Quiet service-category tile: soft disc with a jewel-tone icon.
class CategoryTile extends StatelessWidget {
  final String label;
  final int i;
  final VoidCallback onTap;
  const CategoryTile(this.label, this.i, {super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tone = G.cats[i % G.cats.length][0];
    return Tap(
      scale: .92,
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.line),
                boxShadow: c.lift,
              ),
              alignment: Alignment.center,
              child: HIcon(categoryIcons[label] ?? 'sparkle', size: 24, color: tone),
            ),
            const SizedBox(height: 8),
            Text(
              tr(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.cap(context).copyWith(color: c.ink, fontWeight: FontWeight.w600, fontSize: 14, height: 18 / 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// "850 m" or "2.3 km" away.
String kmLabel(double km) => km < 1 ? tr('{m} m away', {'m': (km * 1000 / 10).round() * 10}) : tr('{km} km away', {'km': km < 10 ? km.toStringAsFixed(1) : km.round()});
