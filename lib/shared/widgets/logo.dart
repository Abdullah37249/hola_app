import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';

/// HOLA® PROFESSIONAL logo. Never recoloured: [white] inverts it on dark/gradient grounds,
/// and it auto-inverts in dark theme.
class Logo extends StatelessWidget {
  final double height;
  final bool white;
  const Logo({super.key, this.height = 30, this.white = false});
  @override
  Widget build(BuildContext context) {
    final img = Image.asset('assets/images/logo.png', height: height, fit: BoxFit.contain);
    if (white || context.c.dark) {
      return ColorFiltered(colorFilter: const ColorFilter.matrix([-1, 0, 0, 0, 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255, 0, 0, 0, 1, 0]), child: img);
    }
    return img;
  }
}
