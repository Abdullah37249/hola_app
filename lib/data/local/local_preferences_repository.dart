import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/repositories.dart';
import 'local_database.dart';

/// App settings in SharedPreferences. Settings saved by older versions inside
/// the data file are moved over once. Until [init] finishes (or if the plugin
/// is unavailable, as in widget tests) the data file is used instead.
class LocalPreferencesRepository implements PreferencesRepository {
  LocalPreferencesRepository(this._db);
  final LocalDatabase _db;
  SharedPreferences? _sp;

  static const _keys = ['theme', 'sound', 'language', 'permissionsAsked'];

  @override
  Future<void> init() async {
    try {
      // Never hold up start-up: fall back to the data file if storage is slow.
      final sp = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      for (final k in _keys) {
        if (sp.containsKey(k) || !_db.prefs.containsKey(k)) continue;
        switch (_db.prefs[k]) {
          case final String v:
            await sp.setString(k, v);
          case final bool v:
            await sp.setBool(k, v);
        }
      }
      _sp = sp;
    } catch (_) {
      _sp = null; // no plugin: keep using the data file
    }
  }

  String _str(String k, String d) => _sp?.getString(k) ?? _db.prefs[k] as String? ?? d;
  bool _bool(String k, bool d) => _sp?.getBool(k) ?? _db.prefs[k] as bool? ?? d;

  void _set(String k, Object v) {
    final sp = _sp;
    if (sp == null) {
      _db.prefs[k] = v;
      _db.commit();
    } else if (v is String) {
      sp.setString(k, v);
    } else if (v is bool) {
      sp.setBool(k, v);
    }
  }

  @override
  String get theme => _str('theme', 'dark');
  @override
  set theme(String v) => _set('theme', v);

  @override
  bool get sound => _bool('sound', true);
  @override
  set sound(bool v) => _set('sound', v);

  @override
  String get language => _str('language', 'en');
  @override
  set language(String v) => _set('language', v);

  @override
  bool get permissionsAsked => _bool('permissionsAsked', false);
  @override
  set permissionsAsked(bool v) => _set('permissionsAsked', v);
}
