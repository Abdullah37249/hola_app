import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/mvvm/view_model.dart';
import '../../core/push/push_events.dart';
import '../../core/security/biometrics.dart';
import '../../core/utils/sfx.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';

/// Who is signed in, which experience and tab is showing, and app preferences.
///
/// The experience comes from the account's role, never from a picker:
/// customer | salon (owner) | sstaff (salon staff) | field (sales officer) | rider.
class SessionViewModel extends ViewModel {
  SessionViewModel(this._auth, this._prefs, [Biometrics? bio]) : _bio = bio ?? Biometrics() {
    _auth.changes.addListener(_onData);
    // Fingerprint sign-in on: locked again after 5 minutes away from the app.
    _life = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: () {
        final away = _hiddenAt == null ? Duration.zero : DateTime.now().difference(_hiddenAt!);
        _hiddenAt = null;
        if (fingerprintOn && !locked && away > relockAfter) {
          locked = true;
          notify();
        }
        // Back in the app while HOLA reviews the salon: maybe it's decided.
        if (awaitingApproval) checkApproval().catchError((Object _) {});
      },
    );
    _pushes = pushEvents.stream.listen((kind) {
      if (kind == 'signup_rejected') {
        _auth.endSessionFromHola();
      } else if (kind == 'salon' && account?.role == Role.salonOwner) {
        checkApproval().catchError((Object _) {});
      }
    });
  }

  StreamSubscription<String>? _pushes;

  /// Time in the background after which fingerprint sign-in locks HOLA again.
  static const relockAfter = Duration(minutes: 5);
  AppLifecycleListener? _life;
  DateTime? _hiddenAt;
  final AuthRepository _auth;
  final PreferencesRepository _prefs;
  final Biometrics _bio;

  bool ready = false;
  String? tab;
  String? _lastAccountId;

  Future<void> init() async {
    await _auth.init();
    await _prefs.init();
    Sfx.enabled = _prefs.sound;
    L10n.lang.value = _prefs.language;
    _lastAccountId = _auth.current?.id;
    // Fingerprint sign-in on: the app opens locked until a fingerprint
    // matches. Otherwise the sensor check runs without holding up start-up.
    if (fingerprintOn || _auth.resumable.isNotEmpty) {
      bioAvailable = await _bio.available();
      // Locked whenever fingerprint sign-in is on, even if the sensor check
      // failed or timed out: the lock screen offers the password instead.
      locked = fingerprintOn;
    } else {
      _bio.available().then((v) {
        bioAvailable = v;
        notify();
      });
    }
    ready = true;
    // Opened while HOLA reviews the salon: ask whether it's decided.
    if (awaitingApproval) checkApproval().catchError((Object _) {});
    notify();
  }

  void _onData() {
    final id = _auth.current?.id;
    if (id != _lastAccountId) {
      _lastAccountId = id;
      tab = null; // new person → start on their first tab
      if (id == null) {
        locked = false;
        offerFingerprint = false;
      }
    }
    notify();
  }

  /// The animated splash has finished (prompts wait for it).
  bool splashDone = false;
  void splashFinished() {
    splashDone = true;
    notify();
  }

  // ── fingerprint sign-in ──

  /// This phone has a fingerprint sensor with a fingerprint set up.
  bool bioAvailable = false;

  /// Opened with fingerprint sign-in on: waiting for a fingerprint.
  bool locked = false;

  /// Just signed in with a password: ask once about fingerprint sign-in.
  bool offerFingerprint = false;

  /// Fingerprint sign-in is on for the signed-in account.
  bool get fingerprintOn => account != null && _auth.fingerprintOn(account!.id);

  /// Signed out: accounts a fingerprint can sign back in ([riders] only,
  /// for the rider sign-in screen).
  List<FingerprintAccount> fingerprintAccounts({bool riders = false}) => !bioAvailable
      ? const []
      : [
          for (final f in _auth.resumable)
            if (!riders || f.role == Role.rider.name) f,
        ];

  /// After a successful password sign-in.
  void passwordSignedIn() {
    final a = account;
    if (a == null || !bioAvailable || fingerprintOn || _auth.fingerprintOffered(a.id)) return;
    offerFingerprint = true;
    notify();
  }

  Future<BioResult> unlock() async {
    final r = await _bio.verify(bio(tr('Unlock HOLA with your fingerprint')));
    if (r == BioResult.ok) {
      locked = false;
      notify();
    }
    return r;
  }

  /// Turns fingerprint sign-in on after the person proves it's their finger.
  Future<BioResult> enableFingerprint() async {
    final r = await _bio.verify(bio(tr('Confirm your fingerprint to turn on fingerprint sign-in')));
    if (r == BioResult.ok) await _auth.enableFingerprint();
    offerFingerprint = false;
    notify();
    return r;
  }

  Future<void> declineFingerprint() async {
    offerFingerprint = false;
    notify();
    if (account case final a?) await _auth.markFingerprintOffered(a.id);
  }

  Future<void> disableFingerprint() async {
    await _auth.disableFingerprint();
    notify();
  }

  /// Signs in with the kept session once a fingerprint matches. Throws a
  /// [DomainError] when the session can't be brought back.
  Future<BioResult> signInWithFingerprint(String accountId) async {
    final r = await _bio.verify(bio(tr('Sign in to HOLA with your fingerprint')));
    if (r == BioResult.ok) await _auth.resumeWithFingerprint(accountId);
    return r;
  }

  /// From the lock screen: sign out to the password sign-in instead.
  Future<void> usePasswordInstead() async {
    locked = false;
    await signOut();
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

  /// A new salon owner's salon waits for HOLA to approve it (0.33.0): until
  /// then the app shows only that, since HOLA refuses every salon action.
  bool get awaitingApproval => account?.role == Role.salonOwner && _auth.usesServer && _auth.mySalonStatus == SalonStatus.pending;

  bool checking = false;

  /// Asks HOLA again whether the salon was approved. Throws a [DomainError]
  /// when HOLA can't be reached.
  Future<void> checkApproval() async {
    if (checking) return;
    checking = true;
    notify();
    try {
      await _auth.refreshMySalon();
    } finally {
      checking = false;
      notify();
    }
  }

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
    _life?.dispose();
    _pushes?.cancel();
    _auth.changes.removeListener(_onData);
    super.dispose();
  }
}
