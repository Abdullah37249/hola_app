import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';

/// Dark gradient card: available credit, usage bar, outstanding and limit.
class CreditCard extends StatelessWidget {
  const CreditCard({super.key, required this.salonId});
  final String salonId;

  @override
  Widget build(BuildContext context) {
    final trade = context.read<TradeRepository>();
    return ListenableBuilder(
      listenable: trade.changes,
      builder: (context, _) => _CreditBody(trade.credit(salonId)),
    );
  }
}

class _CreditBody extends StatelessWidget {
  const _CreditBody(this.cr);
  final CreditSummary cr;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontFamily: T.f, fontSize: 12, height: 16 / 12, color: Color(0xB3FFFFFF));
    const val = TextStyle(fontFamily: T.f, fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white);
    Widget card(Widget child) => HCard(
          gradient: G.credit,
          radius: 20,
          padding: const EdgeInsets.all(20),
          shadow: const [BoxShadow(color: Color(0x5500285A), blurRadius: 28, spreadRadius: -12, offset: Offset(0, 14))],
          child: child,
        );
    if (cr.limit <= 0) {
      return card(Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
          alignment: Alignment.center,
          child: const HIcon('cash', size: 22, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('No HOLA credit yet'), style: T.ttl(context).copyWith(color: Colors.white)),
            Text(tr('Pay cash on delivery. Your sales officer can set up a credit line.'), style: small),
          ]),
        ),
      ]));
    }
    final used = cr.limit == 0 ? 0.0 : cr.outstanding / cr.limit;
    final warn = cr.overdue > 0;
    return card(VStack(gap: 14, [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Available credit'), style: small),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CountUp(cr.available, format: rs, style: T.h1(context).copyWith(color: Colors.white)),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: warn ? const Color(0xFFD9534F) : Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
          child: Text(warn ? tr('{amount} overdue', {'amount': rs(cr.overdue)}) : tr('Nothing overdue'), style: const TextStyle(fontFamily: T.f, fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      ]),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 8,
          color: Colors.white.withValues(alpha: .15),
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: used.clamp(0, 1).toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: kEase,
            builder: (_, v, _) => FractionallySizedBox(widthFactor: v, child: Container(decoration: BoxDecoration(color: used > .9 ? const Color(0xFFE8B98A) : Colors.white.withValues(alpha: .85)))),
          ),
        ),
      ),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('Outstanding'), style: small), FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(rs(cr.outstanding), style: val))])),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('Limit'), style: small), FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(rs(cr.limit), style: val))])),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(tr('Terms'), style: small),
            Text(plural(cr.days, 'day'), style: val),
          ]),
        ),
      ]),
    ]));
  }
}

/// Seven-dot progress along the order flow; red for failed/cancelled.
class OrderProgress extends StatelessWidget {
  const OrderProgress(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bad = status == OrderStatus.cancelled || status == OrderStatus.failed;
    final idx = switch (status) {
      OrderStatus.underReview => 0,
      OrderStatus.failed => 3,
      OrderStatus.cancelled => 0,
      _ => OrderStatus.flow.indexOf(status),
    };
    return Row(children: [
      for (var i = 0; i < OrderStatus.flow.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: i > idx ? c.line : bad && i == idx ? c.bad : i == idx && status != OrderStatus.confirmed ? c.brand.withValues(alpha: .55) : c.brand,
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Order summary card for lists.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, this.onTap, this.showSalon = false});
  final TradeOrder order;
  final VoidCallback? onTap;
  final bool showSalon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final o = order;
    final salon = showSalon ? context.read<SalonRepository>().salon(o.salonId)?.name : null;
    return HCard(
      onTap: onTap,
      child: VStack(gap: 10, [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(salon ?? o.code, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
              Text('${salon != null ? '${o.code} · ' : ''}${dayLabel(o.createdAt, today)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sub(context)),
            ]),
          ),
          const SizedBox(width: 8),
          StatusBadge(o.status),
        ]),
        Row(children: [
          Expanded(child: Text('${plural(o.units, 'unit')} · ${o.isCod ? tr('Cash on delivery') : tr('Credit')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(context).copyWith(color: c.muted))),
          const SizedBox(width: 8),
          Text(rs(o.total), style: T.ttl(context)),
        ]),
        OrderProgress(o.status),
      ]),
    );
  }
}

/// Soft "Buy 6 get 1" pill.
class SchemeBadge extends StatelessWidget {
  const SchemeBadge(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: context.c.accentSoft, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          HIcon('sparkle', size: 12, color: context.c.accentInk),
          const SizedBox(width: 4),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: T.f, fontSize: 11, fontWeight: FontWeight.w700, color: context.c.accentInk))),
        ]),
      );
}

/// Draws a captured signature (strokes in a unit square) inside a box.
class SignatureView extends StatelessWidget {
  const SignatureView(this.strokes, {super.key, this.height = 120});
  final Strokes strokes;
  final double height;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: height,
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      child: CustomPaint(painter: _SigPainter(strokes, c.ink), size: Size.infinite),
    );
  }
}

class _SigPainter extends CustomPainter {
  _SigPainter(this.strokes, this.color);
  final Strokes strokes;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    const pad = 10.0;
    final w = size.width - pad * 2, h = size.height - pad * 2;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      final path = Path()..moveTo(pad + s.first.$1 * w, pad + s.first.$2 * h);
      for (final pt in s.skip(1)) {
        path.lineTo(pad + pt.$1 * w, pad + pt.$2 * h);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_SigPainter old) => old.strokes != strokes || old.color != color;
}

/// Small bottle thumbnail for lists.
class ProductThumb extends StatelessWidget {
  const ProductThumb(this.p, {super.key, this.size = 64});
  final Product p;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size * 1.3,
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Bottle(color: p.color, shape: p.shape, height: size * 1.3, scale: size / 100)),
      );
}
