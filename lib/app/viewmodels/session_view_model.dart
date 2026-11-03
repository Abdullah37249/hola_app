import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/mvvm/view_model.dart';
import '../../core/utils/sfx.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';

/// Who is signed in, which experience and tab is showing, and app preferences.
///
/// The experience comes from the account's role, never from a picker:
/// customer | salon (owner) | sstaff (salon staff) | field (sales officer) | rider.
class SessionViewModel extends ViewModel {
  SessionViewModel(this._auth, this._prefs) {
    _auth.changes.addListener(_onData);
  }
  final AuthRepository _auth;
  final PreferencesRepository _prefs;

  bool ready = false;
  String? tab;
  String? _lastAccountId;

  Future<void> init() async {
    await _auth.init();
    await _prefs.init();
    Sfx.enabled = _prefs.sound;
    L10n.lang.value = _prefs.language;
    _lastAccountId = _auth.current?.id;
    ready = true;
    notify();
  }

  void _onData() {
    final id = _auth.current?.id;
    if (id != _lastAccountId) {
      _lastAccountId = id;
      tab = null; // new person → start on their first tab
    }
    notify();
  }

  Account? get account => _auth.current;
  bool get signedIn => account != null;

  String get rk => switch (account?.role) {
    Role.salonOwner || Role.salonStaff => 'salon',
    Role.salesOfficer => 'field',
    Role.rider => 'rider',
    Role.trainer => 'trainer',
    _ => 'customer',
  };

  /// A salon owner who hasn't created their salon yet goes through set-up first.
  bool get needsSalonSetup => account?.role == Role.salonOwner && account?.salonId == null;

  ThemeMode get themeMode => switch (_prefs.theme) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };
  void setTheme(ThemeMode m) {
    _prefs.theme = switch (m) {
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
      _ => 'light',
    };
    notify();
  }

  String get language => L10n.lang.value;
  void setLanguage(String code) {
    _prefs.language = code;
    L10n.lang.value = code;
    notify();
  }

  /// The one-time permissions screen still has to be shown.
  bool get needsPermissionsIntro => signedIn && !_prefs.permissionsAsked;
  void permissionsIntroShown() => _prefs.permissionsAsked = true;

  bool get sound => Sfx.enabled;
  set sound(bool v) {
    Sfx.enabled = v;
    _prefs.sound = v;
    notify();
  }

  Future<void> signOut() => _auth.signOut();

  void setTab(String id) {
    tab = id;
    notify();
  }

  @override
  void dispose() {
    _auth.changes.removeListener(_onData);
    super.dispose();
  }
}
