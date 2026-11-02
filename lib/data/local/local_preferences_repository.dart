import '../../domain/repositories/repositories.dart';
import 'local_database.dart';

class LocalPreferencesRepository implements PreferencesRepository {
  LocalPreferencesRepository(this._db);
  final LocalDatabase _db;

  @override
  String get theme => _db.prefs['theme'] as String? ?? 'light';
  @override
  set theme(String v) {
    _db.prefs['theme'] = v;
    _db.commit();
  }

  @override
  bool get sound => _db.prefs['sound'] as bool? ?? true;
  @override
  set sound(bool v) {
    _db.prefs['sound'] = v;
    _db.commit();
  }

  @override
  String get language => _db.prefs['language'] as String? ?? 'en';
  @override
  set language(String v) {
    _db.prefs['language'] = v;
    _db.commit();
  }
}
