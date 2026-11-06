import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/photo_files.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../chat/chat.dart';
import '../viewmodels/customer_lookups.dart';
import '../viewmodels/salon_view_model.dart';
import '../widgets/offer_card.dart';
import '../widgets/review_photos.dart';
import '../widgets/salon_cards.dart';
import 'booking_flow_view.dart';

/// Salon profile: branches and hours, contact, menu (multi-select), team,
/// reviews and policies. Selecting services opens a buy bar into booking.
class SalonPage extends StatelessWidget {
  final String id;

  /// A service to start with selected (e.g. booked from an offer).
  final String? select;
  const SalonPage({super.key, required this.id, this.select});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => SalonViewModel(c.read<SalonRepository>(), c.read<AuthRepository>(), c.read<EngagementRepository>(), id, select: select),
    child: const _SalonBody(),
  );
}

class _SalonBody extends StatefulWidget {
  const _SalonBody();
  @override
  State<_SalonBody> createState() => _SalonBodyState();
}

class _SalonBodyState extends State<_SalonBody> {
  final _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _sc.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalonViewModel>();
    final c = context.c;
    final s = vm.s;
    if (s == null) {
      return HPage(
        title: tr('Salon'),
        children: [
          const SizedBox(height: 60),
          EmptyState(icon: 'store', title: tr('Salon not available'), text: tr('This salon is no longer on HOLA.')),
        ],
      );
    }
    final top = MediaQuery.paddingOf(context).top;
    final y = _sc.hasClients ? _sc.offset : 0.0;
    final b = vm.currentBranch;
    final r = vm.rating;
    final hasSel = vm.selected.isNotEmpty;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          ListView(
            controller: _sc,
            padding: EdgeInsets.only(bottom: 140 + MediaQuery.paddingOf(context).bottom),
            children: [
              SizedBox(
                height: 280,
                child: ClipRect(
                  child: Transform.translate(
                    offset: Offset(0, y > 0 ? y * .4 : 0),
                    child: Transform.scale(scale: y < 0 ? 1 - y / 280 : 1, child: _HeroPhotos(s)),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -16),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: const EdgeInsets.fromLTRB(kGutter, 22, kGutter, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...staggered([
                        Text(s.name, style: T.display(context)),
                        if (b != null) ...[
                          const SizedBox(height: 2),
                          Text([b.area, b.city].where((x) => x.isNotEmpty).join(', '), style: T.body(context).copyWith(color: c.muted)),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            RatingOrNew(r),
                            if (r.count > 0) Text(plural(r.count, 'review'), style: T.sm(context).copyWith(color: c.muted)),
                            OpenLine(b),
                            if (s.isActive) ToneBadge(tr('Verified by HOLA'), tone: 'ok'),
                          ],
                        ),
                        if (!s.isListed) ...[
                          const SizedBox(height: 14),
                          HCard(
                            color: c.badSoft,
                            child: Text(tr("This salon isn't taking bookings on HOLA right now."), style: T.sm(context).copyWith(color: c.badInk)),
                          ),
                        ],
                        if (vm.branches.length > 1) ...[
                          const SizedBox(height: 18),
                          Text(tr('BRANCH'), style: T.eyebrow(context)),
                          const SizedBox(height: 8),
                          Seg(opts: [for (final x in vm.branches) (x.id, x.name)], value: b?.id ?? '', onChanged: vm.setBranch),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            if (b != null) ...[Expanded(child: _Action(tr('Directions'), 'nav', onTap: () => _directions(s, b))), const SizedBox(width: 8)],
                            if (s.phone.isNotEmpty) ...[Expanded(child: _Action(tr('Call'), 'phone', onTap: () => showCallSheet(context, s.name, s.phone))), const SizedBox(width: 8)],
                            // HOLA salons are reached in-app once HOLA's chat is live; until then by phone.
                            if (!s.hola || context.read<ChatRepository>().live) Expanded(child: _Action(tr('Message'), 'msg', onTap: () => openSalonChat(context, s.id))),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _UTabs(value: vm.tab, reviews: r.count, onChanged: vm.setTab),
                      ]),
                      KeyedSubtree(
                        key: ValueKey(vm.tab),
                        child: Reveal(child: _tabBody(context, vm, s)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: StatusScrim(
              show: y > 220,
              height: 60,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 120),
                  child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h3(context)),
                ),
              ),
            ),
          ),
          Positioned(
            top: top + 6,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _Fab('back', onTap: () => popPage(context)),
                const Spacer(),
                _Fab(
                  'heart',
                  on: vm.favourite,
                  onTap: () => attempt(() async {
                    final on = await vm.toggleFavourite();
                    if (on) Sfx.add();
                    Fx.toast(on ? tr('Saved to your salons') : tr('Removed from your salons'), icon: 'heart', tone: on ? '' : 'info');
                  }),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: vm.bookable && vm.menu.isNotEmpty || s.hola && s.phone.isNotEmpty ? Offset.zero : const Offset(0, 1.3),
              duration: const Duration(milliseconds: 350),
              curve: kEase,
              // A HOLA salon that hasn't set up its menu yet: call them.
              child: s.hola && vm.menu.isEmpty
                  ? FootBar(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('This salon isn’t taking online bookings yet. Call to book.'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: T.sm(context).copyWith(color: c.muted),
                            ),
                          ),
                          const SizedBox(width: 12),
                          HButton(tr('Call'), icon: 'phone', onTap: () => _call(s.phone)),
                        ],
                      ),
                    )
                  : FootBar(
                      child: Row(
                        children: [
                          Expanded(
                            child: hasSel
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(rs(vm.total), style: T.h2(context)),
                                      ),
                                      Text(
                                        '${plural(vm.selected.length, 'service')} · ${fmtDur(vm.minutes)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: T.sm(context).copyWith(color: c.muted),
                                      ),
                                    ],
                                  )
                                : Text(
                                    tr('Tap + to add services, then pick a time.'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: T.sm(context).copyWith(color: c.muted),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          HButton(
                            tr('Choose time'),
                            icon: 'cal',
                            onTap: b == null || !hasSel ? null : () => pushPage(context, BookingFlowPage(salonId: s.id, branchId: b.id, serviceIds: [for (final x in vm.chosen) x.id])),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _call(String phone) async {
    if (!await launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')))) Fx.toast(tr("Couldn't open the dialler"), icon: 'alert', tone: 'bad');
  }

  Future<void> _directions(Salon s, Branch b) async {
    final q = Uri.encodeComponent('${s.name}, ${b.address}, ${b.area}, ${b.city}');
    final ok = await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'), mode: LaunchMode.externalApplication);
    if (!ok) Fx.toast(tr("Couldn't open Maps on this phone"), icon: 'alert', tone: 'bad');
  }

  Widget _tabBody(BuildContext context, SalonViewModel vm, Salon s) => switch (vm.tab) {
    'team' => _Team(vm),
    'rev' => _Reviews(vm),
    'about' => _About(vm, s),
    _ => _Menu(vm),
  };
}

class _Menu extends StatelessWidget {
  final SalonViewModel vm;
  const _Menu(this.vm);
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final menu = vm.menu;
    final offers = vm.offersByService;
    if (menu.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: EmptyState(icon: 'scissors', title: tr('No services listed'), text: tr("This salon hasn't published its menu yet.")),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (cat, items) in menu) ...[
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 4),
            child: Text(tr(cat).toUpperCase(), style: T.eyebrow(context)),
          ),
          for (final x in items)
            Tap(
              scale: .99,
              onTap: vm.bookable ? () => vm.toggle(x.id) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(x.name, style: T.ttl(context).copyWith(color: vm.selected.contains(x.id) ? c.brandText : c.ink)),
                          Text([fmtDur(x.durationMin), if (x.description.isNotEmpty) x.description].join(' · '), style: T.sm(context).copyWith(color: c.muted)),
                          const SizedBox(height: 2),
                          _Price(x, offers[x.id], vm),
                        ],
                      ),
                    ),
                    if (vm.bookable) ...[const SizedBox(width: 12), _Check(on: vm.selected.contains(x.id))],
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// A service's price; with a running offer, the old price struck through,
/// the new one, and the offer (or why this customer can't use it again).
class _Price extends StatelessWidget {
  const _Price(this.x, this.offer, this.vm);
  final ServiceItem x;
  final ServiceOffer? offer;
  final SalonViewModel vm;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final o = offer;
    final plain = Text(
      rs(x.price),
      style: T.sm(context).copyWith(color: c.ink, fontWeight: FontWeight.w600),
    );
    if (o == null) return plain;
    final use = vm.offerUse(o);
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(gradient: offerGradient, borderRadius: BorderRadius.circular(6)),
      child: Text(
        '${offText(o)} · ${tr('until {date}', {'date': dayMonth(o.lastDay)})}',
        style: T.cap(context).copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
    if (use != OfferUse.none) {
      final held = vm.offerHeldOn(o);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          plain,
          Text(
            use == OfferUse.used
                ? tr('You have already used the {off} offer', {'off': offText(o)})
                : held.isEmpty
                ? tr('{off} offer held for one of your bookings', {'off': offText(o)})
                : tr('{off} offer held for {code}', {'off': offText(o), 'code': held}),
            style: T.cap(context),
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          rs(x.price),
          style: T.sm(context).copyWith(color: c.muted, decoration: TextDecoration.lineThrough),
        ),
        Text(
          rs(x.price - o.discountOn(x.price)),
          style: T.sm(context).copyWith(color: c.ink, fontWeight: FontWeight.w700),
        ),
        tag,
      ],
    );
  }
}

class _Check extends StatelessWidget {
  final bool on;
  const _Check({required this.on});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: kEase,
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? c.brand : c.surface,
        border: Border.all(color: on ? c.brand : c.brandLine, width: 1.5),
      ),
      alignment: Alignment.center,
      child: HIcon(on ? 'check' : 'plus', size: 18, stroke: 2.4, color: on ? Colors.white : c.brandText),
    );
  }
}

class _Team extends StatelessWidget {
  final SalonViewModel vm;
  const _Team(this.vm);
  @override
  Widget build(BuildContext context) {
    final pros = vm.pros;
    if (pros.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: EmptyState(icon: 'users', title: tr('No team listed'), text: tr('The salon will assign a professional when you book.')),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Group(
        children: [
          for (final (p, name) in pros)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Avatar(name, size: 46, k: name.length),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: T.ttl(context)),
                        Text(p.title.isEmpty ? tr('Professional') : p.title, style: T.sm(context).copyWith(color: context.c.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Reviews extends StatelessWidget {
  final SalonViewModel vm;
  const _Reviews(this.vm);
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rs0 = vm.reviews;
    if (rs0.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: EmptyState(icon: 'star', title: tr('No reviews yet'), text: tr('Reviews come from customers after a completed visit.')),
      );
    }
    final r = vm.rating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        HCard(
          child: Row(
            children: [
              Text(r.average.toStringAsFixed(1), style: T.display(context)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stars(r.average.round(), size: 18),
                    const SizedBox(height: 4),
                    Text(tr('From {visits}', {'visits': plural(r.count, 'verified visit')}), style: T.sm(context).copyWith(color: c.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final x in rs0) ReviewTile(x),
      ],
    );
  }
}

/// One review with the salon's reply, if any.
class ReviewTile extends StatelessWidget {
  final Review r;
  final String? salonName;
  const ReviewTile(this.r, {super.key, this.salonName});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(r.customerName, size: 34, k: r.customerName.length),
              const SizedBox(width: 10),
              Expanded(
                child: Text(r.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
              ),
              Text(ago(r.createdAt, now()), style: T.cap(context)),
            ],
          ),
          const SizedBox(height: 8),
          Stars(r.stars),
          if (r.text.isNotEmpty) ...[const SizedBox(height: 6), Text(r.text, style: T.body(context))],
          if (r.photos.isNotEmpty) ...[const SizedBox(height: 10), ReviewPhotoStrip(r)],
          if (r.reply != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Reply from {salon}', {'salon': salonName ?? tr('the salon')}),
                    style: T.cap(context).copyWith(color: c.brandText, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(r.reply!, style: T.sm(context).copyWith(color: c.ink)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _About extends StatelessWidget {
  final SalonViewModel vm;
  final Salon s;
  const _About(this.vm, this.s);
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final b = vm.currentBranch;
    final wd = now().weekday - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        if (s.about.isNotEmpty) ...[Text(s.about, style: T.body(context)), const SizedBox(height: 18)],
        if (b != null) ...[
          Text(tr('ADDRESS'), style: T.eyebrow(context)),
          const SizedBox(height: 8),
          SelectableText([b.address, b.area, b.city].where((x) => x.isNotEmpty).join(', '), style: T.body(context).copyWith(color: c.ink)),
          const SizedBox(height: 18),
          Text(tr('OPENING HOURS · {branch}', {'branch': b.name.toUpperCase()}), style: T.eyebrow(context)),
          const SizedBox(height: 8),
          HCard(
            child: Column(
              children: [
                for (var i = 0; i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr(weekdayNames[i]),
                            style: T.sm(context).copyWith(color: i == wd ? c.brandText : c.body, fontWeight: i == wd ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ),
                        Text(
                          shiftLabel(b.hours[i]),
                          style: T.sm(context).copyWith(color: b.hours[i] == null ? c.muted : c.ink, fontWeight: i == wd ? FontWeight.w700 : FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        Text(tr('BOOKING POLICY'), style: T.eyebrow(context)),
        const SizedBox(height: 8),
        Group(
          children: [
            MRow(
              icon: 'check',
              tint: 3,
              title: s.autoConfirm ? tr('Instant confirmation') : tr('Salon confirms each request'),
              sub: s.autoConfirm ? tr('Your booking is confirmed straight away.') : tr("You'll get a notification once they confirm."),
            ),
            MRow(
              icon: 'clock',
              tint: 2,
              title: s.cancelWindowHours == 0 ? tr('Cancel any time') : tr('Free cancellation up to {hours} before', {'hours': plural(s.cancelWindowHours, 'hour')}),
              sub: tr('Pay at the salon after your service.'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final String label, icon;
  final VoidCallback onTap;
  const _Action(this.label, this.icon, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Column(
          children: [
            HIcon(icon, size: 20, color: c.brandText),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.sm(context).copyWith(fontWeight: FontWeight.w600, color: c.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  final String icon;
  final bool on;
  final VoidCallback onTap;
  const _Fab(this.icon, {this.on = false, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tap(
      onTap: onTap,
      scale: .9,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(on),
        tween: Tween(begin: on ? 1.35 : 1, end: 1),
        duration: const Duration(milliseconds: 400),
        curve: kSpring,
        builder: (_, v, child) => Transform.scale(scale: v, child: child),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.glass, shape: BoxShape.circle, boxShadow: c.lift),
          alignment: Alignment.center,
          child: HIcon(icon, size: 22, fill: on, color: on ? c.bad : c.ink),
        ),
      ),
    );
  }
}

class _UTabs extends StatelessWidget {
  final String value;
  final int reviews;
  final ValueChanged<String> onChanged;
  const _UTabs({required this.value, required this.reviews, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final opts = [
      ('svc', tr('Services')),
      ('team', tr('Team')),
      ('rev', reviews > 0 ? tr('Reviews ({n})', {'n': reviews}) : tr('Reviews')),
      ('about', tr('About')),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final o in opts)
              Padding(
                padding: const EdgeInsets.only(right: 22),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (o.$1 != value) {
                      Sfx.tap();
                      onChanged(o.$1);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(fontFamily: T.f, fontSize: 15, fontWeight: FontWeight.w600, color: o.$1 == value ? c.ink : c.muted),
                          child: Text(o.$2),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: kEase,
                        height: 2,
                        width: o.$1 == value ? 40 : 0,
                        decoration: BoxDecoration(gradient: G.btn, borderRadius: BorderRadius.circular(2)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Call the salon": shows the number, places the call or copies it.
void showCallSheet(BuildContext context, String name, String number) {
  showHSheet(
    context,
    (ctx) => VStack(gap: 14, [
      SheetHead(tr('Call {name}', {'name': name})),
      SelectableText(number, style: T.display(ctx)),
      HButton(
        tr('Call now'),
        icon: 'phone',
        block: true,
        onTap: () async {
          final ok = await launchUrl(Uri(scheme: 'tel', path: number.replaceAll(RegExp(r'[^0-9+]'), '')));
          if (ctx.mounted) Navigator.pop(ctx);
          if (!ok) Fx.toast(tr("This phone can't place calls"), icon: 'alert', tone: 'bad');
        },
      ),
      HButton(
        tr('Copy number'),
        kind: BtnKind.secondary,
        block: true,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: number));
          if (ctx.mounted) Navigator.pop(ctx);
          Fx.toast(tr('Number copied'));
        },
      ),
    ]),
  );
}

/// Salon cover, or a swipeable gallery with page dots when there are several photos.
class _HeroPhotos extends StatefulWidget {
  final Salon s;
  const _HeroPhotos(this.s);
  @override
  State<_HeroPhotos> createState() => _HeroPhotosState();
}

class _HeroPhotosState extends State<_HeroPhotos> {
  int _page = 0;
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final photos = s.photos.where((p) => PhotoFiles.file(p) != null).toList();
    if (photos.length < 2) return SalonArt(s.palette, photo: s.cover, radius: 0, name: s.name);
    return Stack(
      children: [
        PageView(
          onPageChanged: (i) => setState(() => _page = i),
          children: [for (final p in photos) SalonArt(s.palette, photo: p, radius: 0)],
        ),
        // Sits above the page sheet's rounded top edge.
        Positioned(
          left: 0,
          right: 0,
          bottom: 30,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < photos.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: kEase,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: i == _page ? 1 : .55),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
