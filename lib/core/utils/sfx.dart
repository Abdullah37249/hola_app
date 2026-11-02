import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Synthesised UI sounds + haptics, ported from the prototype's Web Audio `sfx`.
/// Tones are rendered once to small WAV buffers and replayed from memory.
class Sfx {
  Sfx._();
  static bool enabled = true;
  static final Map<String, Uint8List> _cache = {};
  static final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer()..setReleaseMode(ReleaseMode.stop));
  static int _next = 0;

  static void tap() { _play('tap', [1250], .035, _Wave.sine, .022); _haptic(HapticFeedback.selectionClick); }
  static void nav() => _play('nav', [620, 930], .09, _Wave.sine, .028, .045);
  static void back() => _play('back', [930, 620], .09, _Wave.sine, .024, .045);
  static void sheet() => _play('sheet', [420, 560], .12, _Wave.sine, .028, .05);
  static void toggle() { _play('toggle', [880], .05, _Wave.triangle, .03); _haptic(HapticFeedback.lightImpact); }
  static void add() { _play('add', [700, 1050], .07, _Wave.sine, .035, .04); _haptic(HapticFeedback.lightImpact); }
  static void success() { _play('success', [523.25, 659.25, 783.99, 1046.5], .26, _Wave.triangle, .045, .085); _haptic(HapticFeedback.mediumImpact); }
  static void soft() => _play('soft', [783.99, 1046.5], .16, _Wave.sine, .03, .07);
  static void error() { _play('error', [233, 196], .16, _Wave.square, .018, .1); _haptic(HapticFeedback.heavyImpact); }
  static void tick() => _play('tick', [1800], .02, _Wave.sine, .015);

  static void _haptic(Future<void> Function() f) { if (enabled) f(); }

  static void _play(String key, List<double> fs, double dur, _Wave w, double vol, [double gap = .06]) {
    if (!enabled) return;
    final bytes = _cache.putIfAbsent(key, () => _render(fs, dur, w, vol * 9, gap));
    final p = _pool[_next++ % _pool.length];
    p.play(BytesSource(bytes, mimeType: 'audio/wav')).catchError((_) {});
  }

  static Uint8List _render(List<double> fs, double dur, _Wave w, double vol, double gap) {
    const sr = 22050;
    final total = ((fs.length - 1) * gap + dur + .04) * sr;
    final n = total.ceil();
    final buf = Float64List(n);
    for (var i = 0; i < fs.length; i++) {
      final start = (i * gap * sr).round();
      final len = ((dur + .03) * sr).round();
      for (var j = 0; j < len && start + j < n; j++) {
        final t = j / sr;
        final env = t < .008 ? t / .008 : math.pow(.0001 / 1, (t - .008) / (dur - .008)).toDouble();
        final ph = 2 * math.pi * fs[i] * t;
        double s;
        switch (w) {
          case _Wave.sine: s = math.sin(ph);
          case _Wave.triangle: s = 2 / math.pi * math.asin(math.sin(ph));
          case _Wave.square: s = math.sin(ph) >= 0 ? 1 : -1;
        }
        buf[start + j] += s * env * vol;
      }
    }
    final data = ByteData(44 + n * 2);
    void str(int o, String s) { for (var i = 0; i < s.length; i++) { data.setUint8(o + i, s.codeUnitAt(i)); } }
    str(0, 'RIFF'); data.setUint32(4, 36 + n * 2, Endian.little); str(8, 'WAVE'); str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little); data.setUint16(20, 1, Endian.little); data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sr, Endian.little); data.setUint32(28, sr * 2, Endian.little); data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little); str(36, 'data'); data.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      data.setInt16(44 + i * 2, (buf[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }
}

enum _Wave { sine, triangle, square }
