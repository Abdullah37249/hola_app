import 'package:flutter/material.dart';

import '../../core/utils/location.dart';
import '../../core/utils/sfx.dart';
import '../../domain/entities/geo.dart';
import 'ui.dart';

/// "Capture GPS" for an address: reads the phone's location once (stand at
/// the salon's door) and shows what was saved, with a way to capture again.
/// Riders use it to navigate straight to the salon.
class GpsCapture extends StatefulWidget {
  final GeoFix? value;
  final ValueChanged<GeoFix> onChanged;
  const GpsCapture({super.key, required this.value, required this.onChanged});
  @override
  State<GpsCapture> createState() => _GpsCaptureState();
}

class _GpsCaptureState extends State<GpsCapture> {
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    final fix = await Location.read();
    if (!mounted) return;
    setState(() => _busy = false);
    if (fix == null) {
      Fx.toast(tr('Turn on location and allow HOLA to use it, then try again'), icon: 'alert', tone: 'bad');
      return;
    }
    Sfx.success();
    widget.onChanged(fix);
    Fx.toast(tr('Location captured'), icon: 'pin');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final v = widget.value;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: v == null ? c.surface2 : c.okSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: v == null ? c.line : c.ok.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: v == null ? c.brandSoft : c.ok.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: HIcon(v == null ? 'pin' : 'check', size: 20, color: v == null ? c.brand : c.ok),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(v == null ? tr('GPS location') : tr('GPS location saved'), style: T.ttl(context)),
                Text(v == null ? tr('Stand at the salon door and capture it. Riders use it to find you.') : v.label, style: T.cap(context)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
              : HButton(v == null ? tr('Capture GPS') : tr('Again'), icon: v == null ? 'pin' : null, small: true, kind: v == null ? BtnKind.primary : BtnKind.secondary, onTap: _capture),
        ],
      ),
    );
  }
}
