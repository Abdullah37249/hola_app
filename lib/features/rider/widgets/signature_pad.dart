import 'package:flutter/material.dart';

import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/ui.dart';

/// Finger-drawn signature box. Reports points in the pad's unit square (0..1)
/// so the signature renders the same at any size.
class SignaturePad extends StatelessWidget {
  final List<List<Offset>> strokes;
  final ValueChanged<Offset> onStart, onUpdate;
  final double height;
  const SignaturePad({super.key, required this.strokes, required this.onStart, required this.onUpdate, this.height = 180});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: height,
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line), boxShadow: c.lift),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, k) {
        Offset unit(Offset p) => Offset((p.dx / k.maxWidth).clamp(0, 1), (p.dy / k.maxHeight).clamp(0, 1));
        return GestureDetector(
          onPanStart: (e) => onStart(unit(e.localPosition)),
          onPanUpdate: (e) => onUpdate(unit(e.localPosition)),
          child: CustomPaint(
            painter: SignaturePainter(strokes, c.ink),
            child: Stack(children: [
              // Signing line
              Positioned(left: 20, right: 20, bottom: 34, child: Container(height: 1, color: c.line)),
              Positioned(left: 20, bottom: 12, child: Text(tr('Sign above the line'), style: T.cap(context).copyWith(color: c.subtle))),
              if (strokes.isEmpty) Center(child: Row(mainAxisSize: MainAxisSize.min, children: [HIcon('edit', size: 18, color: c.subtle), const SizedBox(width: 6), Text(tr('Recipient signs here'), style: T.sub(context).copyWith(color: c.subtle))])),
            ]),
          ),
        );
      }),
    );
  }
}

/// Read-only rendering of a stored signature.
class SignatureView extends StatelessWidget {
  final Strokes strokes;
  final double height;
  const SignatureView(this.strokes, {super.key, this.height = 120});
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(color: context.c.surface2, borderRadius: BorderRadius.circular(14)),
        child: CustomPaint(painter: SignaturePainter([for (final s in strokes) [for (final p in s) Offset(p.$1, p.$2)]], context.c.ink), child: const SizedBox.expand()),
      );
}

/// Paints unit-square strokes scaled to the canvas.
class SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color color;
  SignaturePainter(this.strokes, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    Offset at(Offset u) => Offset(u.dx * size.width, u.dy * size.height);
    for (final s in strokes) {
      if (s.isEmpty) continue;
      final path = Path()..moveTo(at(s.first).dx, at(s.first).dy);
      for (final o in s.skip(1)) {
        path.lineTo(at(o).dx, at(o).dy);
      }
      if (s.length == 1) path.lineTo(at(s.first).dx + .5, at(s.first).dy);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter old) => true;
}
