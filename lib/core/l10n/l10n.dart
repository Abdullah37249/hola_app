import 'package:flutter/widgets.dart';

import 'ur_auth.dart';
import 'ur_common.dart';
import 'ur_customer.dart';
import 'ur_data.dart';
import 'ur_field.dart';
import 'ur_rider.dart';
import 'ur_salon.dart';
import 'ur_salon2.dart';
import 'ur_trade.dart';

/// App language. English text is the key; Urdu comes from the ur_*.dart maps.
abstract final class L10n {
  /// 'en' or 'ur'. Set from the saved preference at start and from Settings.
  static final lang = ValueNotifier<String>('en');
  static bool get ur => lang.value == 'ur';
  static const supported = [Locale('en'), Locale('ur')];

  /// Every Urdu string, merged from the per-area maps.
  static final Map<String, String> urdu = {...urCommon, ...urAuth, ...urCustomer, ...urSalon, ...urSalon2, ...urField, ...urTrade, ...urRider, ...urData};
}

/// Translates [en] into the current language, then fills `{placeholders}`
/// from [args]. Text without an Urdu entry stays in English, never blank.
///
///     tr('Welcome back, {name}', {'name': first})
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = L10n.ur ? (L10n.urdu[en] ?? en) : en;
  for (final e in args.entries) {
    s = s.replaceAll('{${e.key}}', '${e.value}');
  }
  return s;
}
