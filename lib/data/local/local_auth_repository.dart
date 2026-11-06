import 'package:flutter/foundation.dart';

import '../../core/l10n/l10n.dart';
import '../../core/security/sha256.dart';
import '../../core/utils/clock.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import 'local_database.dart';
import '../../core/network/api.dart';
import 'hola_mirror.dart';
import 'hola_salon_sync.dart';
import 'fingerprint_store.dart';
import '../../core/security/biometrics.dart' show bio;

/// Shared plumbing for the on-device repositories.
abstract class LocalRepository implements Observable {
  LocalRepository(this.db);
  final LocalDatabase db;

  @override
  Listenable get changes => db;

  Account? get me => db.sessionAccountId == null ? null : db.accounts.where((a) => a.id == db.sessionAccountId).firstOrNull;
  Account get requireMe => me ?? (throw DomainError(tr('Please sign in again.')));

  void requireRole(Set<Role> roles) {
    if (!roles.contains(requireMe.role)) throw DomainError(tr("Your account can't do that."));
  }
}

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
String normEmail(String e) => e.trim().toLowerCase();

void validateEmail(String email) {
  if (!_email.hasMatch(email.trim())) throw DomainError(tr('Enter a valid email address.'), field: 'email');
}

void validatePassword(String p) {
  if (p.length < 8) throw DomainError(tr('Use at least 8 characters for the password.'), field: 'password');
}

void validatePhone(String p) {
  if (p.replaceAll(RegExp(r'[^0-9]'), '').length < 10) throw DomainError(tr('Enter a valid phone number.'), field: 'phone');
}

class LocalAuthRepository extends LocalRepository implements AuthRepository {
  /// With [api], every sign-in and customer sign-up is checked by the HOLA
  /// server (owner's rule: no accounts that exist only on the phone) and the
  /// account is mirrored here for the screens. Without it (tests), accounts
  /// live on the device only.
  LocalAuthRepository(super.db, {this.api, FingerprintStore? fingerprints}) : _fpStore = fingerprints ?? (api == null ? MemoryFingerprintStore() : SecureFingerprintStore()) {
    // The session ended on the server (refresh refused): nothing of that
    // account stays on the phone.
    api?.onSessionEnded = () => db.wipeAccountData();
  }
  final HolaApi? api;

  // ── fingerprint sign-in ──

  final FingerprintStore _fpStore;
  List<FingerprintAccount> _fps = [];

  /// Accounts with a kept session (signed out, fingerprint sign-in on).
  final _parked = <String>{};
  Set<String> _offered = {};

  @override
  bool fingerprintOn(String accountId) => _fps.any((f) => f.accountId == accountId);

  @override
  List<FingerprintAccount> get resumable => me != null
      ? const []
      : [
          for (final f in _fps)
            if (_parked.contains(f.accountId)) f,
        ];

  @override
  bool fingerprintOffered(String accountId) => _offered.contains(accountId);

  @override
  Future<void> markFingerprintOffered(String accountId) async {
    _offered.add(accountId);
    await _fpStore.addOffered(accountId);
  }

  @override
  Future<void> enableFingerprint() async {
    final a = requireMe;
    if (api == null) throw DomainError(bio(tr('Fingerprint sign-in works with your HOLA account only.')));
    _fps = [..._fps.where((f) => f.accountId != a.id), FingerprintAccount(accountId: a.id, name: a.name, email: a.email, role: a.role.name)];
    await _fpStore.write(_fps);
    await markFingerprintOffered(a.id);
    db.commit();
  }

  @override
  Future<void> disableFingerprint([String? accountId]) async {
    final id = accountId ?? requireMe.id;
    _fps = _fps.where((f) => f.accountId != id).toList();
    _parked.remove(id);
    await _fpStore.write(_fps);
    await api?.dropParked(id);
    db.commit();
  }

  @override
  Future<Account> resumeWithFingerprint(String accountId) async {
    if (api == null || !fingerprintOn(accountId) || !_parked.contains(accountId)) throw DomainError(tr('Sign in with your email and password.'));
    try {
      final a = await _serverSignIn(() => api!.resumeParked(accountId));
      _parked.remove(accountId);
      await api!.forgetParked(accountId);
      return a;
    } on DomainError catch (e) {
      // HOLA ended the session (30 days unused, password changed, signed out
      // everywhere): fingerprint sign-in starts again after a password sign-in.
      if (!await api!.hasParked(accountId)) {
        _fps = _fps.where((f) => f.accountId != accountId).toList();
        _parked.remove(accountId);
        await _fpStore.write(_fps);
        db.commit();
        throw DomainError(bio(tr('Your fingerprint sign-in has expired. Sign in with your password, then turn it on again in Settings.')));
      }
      throw DomainError(e.message);
    }
  }

  @override
  Future<void> init() async {
    await db.load();
    if (api != null) {
      _fps = await _fpStore.read();
      _offered = await _fpStore.offered();
      for (final f in _fps) {
        if (await api!.hasParked(f.accountId)) _parked.add(f.accountId);
      }
    }
    // A session without server tokens (from before sign-in moved to HOLA) must sign in again.
    if (api != null && db.sessionAccountId != null && !await api!.hasSession) {
      db.sessionAccountId = null;
      db.commit();
    }
    // Team members no longer sign in; the salon account manages them.
    if (me?.role == Role.salonStaff) {
      db.sessionAccountId = null;
      db.commit();
    }
  }

  @override
  Account? get current => me;

  @override
  bool get usesServer => api != null;

  @override
  Future<void> requestPasswordReset(String email) async {
    validateEmail(email);
    try {
      await api!.post('/auth/password/forgot', {'email': normEmail(email)}, auth: false);
    } catch (e) {
      throw apiToDomain(e);
    }
  }

  @override
  Account? account(String id) => db.accounts.where((a) => a.id == id).firstOrNull;

  @override
  List<Account> accountsWithRole(Role role) => db.accounts.where((a) => a.role == role).toList();

  Account? _byEmail(String email) => normEmail(email).isEmpty ? null : db.accounts.where((a) => a.email == normEmail(email)).firstOrNull;

  @override
  Future<Account> signIn(String email, String password) async {
    if (api != null) {
      final a = await _serverSignIn(() => api!.login(normEmail(email), password));
      // A fresh password sign-in replaces this account's kept session. Other
      // accounts' fingerprint sign-ins stay as they are.
      if (_parked.remove(a.id)) await api!.forgetParked(a.id);
      return a;
    }
    final a = _byEmail(email);
    if (a == null || hashPassword(password, a.salt) != a.passwordHash) throw DomainError(tr('Email or password is incorrect.'), field: 'password');
    if (a.role == Role.salonStaff) throw DomainError(tr('Team members don’t sign in. Your salon manages your appointments on HOLA.'), field: 'email');
    db.sessionAccountId = a.id;
    db.commit();
    return a;
  }

  @override
  Future<Account> signUp({required Role role, required String name, required String email, required String phone, required String password, String city = '', SalonDraft? salon}) async {
    if (api != null) {
      if (!Role.signUp.contains(role)) throw DomainError(tr('HOLA creates officer and rider accounts. Sign in with the details HOLA gave you.'));
      if (name.trim().length < 2) throw DomainError(tr('Enter your full name.'), field: 'name');
      validateEmail(email);
      validatePhone(phone);
      validatePassword(password);
      if (role == Role.salonOwner) {
        if (salon == null || salon.name.trim().length < 2) throw DomainError(tr('Enter your salon’s name.'), field: 'salonName');
        if (city.trim().length < 2) throw DomainError(tr('Enter the city.'), field: 'city');
      }
      final a = await _serverSignIn(
        () => role == Role.salonOwner
            ? api!.registerSalon(
                email: normEmail(email),
                password: password,
                fullName: name.trim(),
                phone: _apiPhone(phone),
                salon: {
                  'name': salon!.name.trim(),
                  'phone': _apiPhone(phone),
                  'mainBranch': {
                    'name': salon.area.trim().isEmpty ? city.trim() : salon.area.trim(),
                    if (salon.address.trim().isNotEmpty) 'addressLine': salon.address.trim(),
                    if (salon.area.trim().isNotEmpty) 'area': salon.area.trim(),
                    'city': city.trim(),
                    'phone': _apiPhone(phone),
                    // The door's GPS, so HOLA's riders can navigate here.
                    if (salon.location case final at?) ...{'latitude': at.lat, 'longitude': at.lng},
                  },
                },
              )
            : api!.register(email: normEmail(email), password: password, fullName: name.trim(), phone: _apiPhone(phone)),
        city: city,
      );
      final at = salon?.location;
      final b = at == null ? null : db.branches.where((x) => x.salonId == a.salonId).firstOrNull;
      if (b != null) b.location = at;
      db.notify(a.id, 'Welcome to HOLA, {name}', _welcome(role), args: {'name': a.firstName}, icon: 'sparkle');
      db.commit();
      return a;
    }
    if (!Role.signUp.contains(role)) {
      throw DomainError(role == Role.salonStaff ? tr('Team members are added by their salon.') : tr('HOLA creates officer and rider accounts. Sign in with the details HOLA gave you.'));
    }
    final a = createAccount(db, role: role, name: name, email: email, phone: phone, password: password, city: city);
    db.sessionAccountId = a.id;
    db.notify(a.id, 'Welcome to HOLA, {name}', _welcome(role), args: {'name': a.firstName}, icon: 'sparkle');
    db.commit();
    return a;
  }

  // ── HOLA server ──

  static const _fields = {
    'fullName': 'name',
    'email': 'email',
    'password': 'password',
    'phone': 'phone',
    'salon.name': 'salonName',
    'salon.mainBranch.city': 'city',
    'salon.mainBranch.addressLine': 'address',
    'salon.mainBranch.area': 'area',
  };

  /// The API wants digits with an optional leading + (e.g. +923001112233).
  String _apiPhone(String p) => p.replaceAll(RegExp(r'[^0-9+]'), '');

  /// Gets tokens with [getTokens], reads who it is from GET /me and mirrors
  /// that account (and a salon owner's salon) on the phone.
  Future<Account> _serverSignIn(Future<void> Function() getTokens, {String city = ''}) async {
    try {
      await getTokens();
      final me = await api!.get('/me') as J;
      final role = _roleOf(me);
      String? salonId;
      if (role == Role.salonOwner) salonId = await _mirrorMySalon(me['id'] as String);
      final a = _mirrorAccount(me, role, salonId: salonId, city: city);
      db.sessionAccountId = a.id;
      db.commit();
      return a;
    } on DomainError {
      await api!.clearSession();
      rethrow;
    } catch (e) {
      await api!.clearSession();
      throw apiToDomain(e, fieldNames: _fields);
    }
  }

  Role _roleOf(J me) {
    final roles = [for (final r in (me['roles'] as List? ?? const [])) (r as Map)['role'] as String];
    final perms = {for (final p in (me['permissions'] as List? ?? const [])) '$p'};
    return switch (me['kind']) {
      'CUSTOMER' => Role.customer,
      'SALON' when roles.contains('SALON_OWNER') || roles.contains('SALON_MANAGER') => Role.salonOwner,
      'SALON' => throw DomainError(tr('Team members don’t sign in. Your salon manages your appointments on HOLA.')),
      // HOLA staff go by permission, in this order (admins hold all of them
      // and land on the officer home): visits → officer, training → trainer,
      // deliveries → rider.
      'EMPLOYEE' when perms.contains('visits.manage') || roles.contains('SALES_OFFICER') => Role.salesOfficer,
      'EMPLOYEE' when perms.contains('training.manage') || roles.contains('TRAINER') => Role.trainer,
      'EMPLOYEE' when perms.contains('deliveries.own') || roles.contains('DELIVERY_RIDER') => Role.rider,
      // Other office staff work in the portal; sign-in stops here and signs out.
      _ => throw DomainError(tr('Use the HOLA portal. This account is for the HOLA office, not the app.')),
    };
  }

  Account _mirrorAccount(J me, Role role, {String? salonId, String city = ''}) {
    final id = me['id'] as String;
    final existing = account(id);
    if (existing != null) {
      existing
        ..email = normEmail(me['email'] as String? ?? existing.email)
        ..name = (me['fullName'] as String?) ?? existing.name
        ..phone = (me['phone'] as String?) ?? existing.phone;
      if (salonId != null) existing.salonId = salonId;
      return existing;
    }
    // Another phone-only account with the same email would shadow this one.
    db.accounts.removeWhere((a) => a.email == normEmail(me['email'] as String? ?? ''));
    final a = Account(
      id: id,
      email: normEmail(me['email'] as String? ?? ''),
      name: me['fullName'] as String? ?? '',
      phone: me['phone'] as String? ?? '',
      role: role,
      passwordHash: '', // the server checks passwords
      salt: '',
      salonId: salonId,
      city: city,
      createdAt: DateTime.tryParse(me['createdAt'] as String? ?? '') ?? now(),
    );
    db.accounts.add(a);
    return a;
  }

  /// Mirrors the owner's salon (from /me/salons, with branches and menu from
  /// the directory when it's live) so the salon screens work.
  /// Returns its id, or null when the account has no salon yet.
  Future<String?> _mirrorMySalon(String ownerId) async {
    final list = await api!.get('/me/salons') as List;
    if (list.isEmpty) return null;
    final s = (list.first as Map)['salon'] as Map;
    final id = s['id'] as String;
    final status = switch (s['status']) {
      'ACTIVE' => SalonStatus.active,
      'SUSPENDED' => SalonStatus.suspended,
      _ => SalonStatus.pending,
    };
    if (status == SalonStatus.active) {
      try {
        await mirrorDiscoverSalon(db, api!, await api!.get('/discover/salons/$id', auth: false) as J, ownerId: ownerId);
      } catch (_) {}
    }
    var salon = db.salons.where((x) => x.id == id).firstOrNull;
    if (salon == null) {
      salon = Salon(id: id, ownerId: ownerId, name: s['name'] as String? ?? '', phone: s['phone'] as String? ?? '', status: status, palette: db.salons.length % 6, hola: true, createdAt: now());
      db.salons.add(salon);
    }
    salon
      ..name = s['name'] as String? ?? salon.name
      ..phone = s['phone'] as String? ?? salon.phone
      ..status = status;
    if (salon.ownerId != ownerId) {
      final i = db.salons.indexOf(salon);
      db.salons[i] = Salon.fromJson({...salon.toJson(), 'ownerId': ownerId});
    }
    if (!db.branches.any((b) => b.salonId == id)) {
      db.branches.add(Branch(id: db.newId(), salonId: id, name: tr('Main'), address: '', area: '', city: s['city'] as String? ?? ''));
    }
    // The team as the server has it (names, titles, hours); the owner is the
    // first stylist of a new salon.
    if (status == SalonStatus.active) {
      try {
        final sync = HolaSalonSync(db, api!);
        await sync.ensureOwnerBookable(id, ownerId);
        await sync.pullTeam(id);
      } catch (_) {}
    }
    // The server lists bookable stylists (the owner's member record included);
    // only a salon with none yet gets the owner as its first professional.
    if (!db.staff.any((p) => p.salonId == id)) {
      final b = db.branches.where((x) => x.salonId == id).firstOrNull;
      db.staff.add(StaffProfile(accountId: ownerId, salonId: id, title: 'Owner', week: [...?b?.hours], createdAt: now()));
    }
    return id;
  }

  /// Creates a sales officer or rider account without signing in. Stands in
  /// for HOLA creating these accounts on its server until the API is
  /// connected; there is no way to reach it from the app's screens.
  Future<Account> provision({required Role role, required String name, required String email, required String phone, required String password, String city = ''}) async {
    if (!{Role.salesOfficer, Role.rider, Role.trainer}.contains(role)) throw DomainError(tr("Your account can't do that."));
    final a = createAccount(db, role: role, name: name, email: email, phone: phone, password: password, city: city);
    db.notify(a.id, 'Welcome to HOLA, {name}', _welcome(role), args: {'name': a.firstName}, icon: 'sparkle');
    db.commit();
    return a;
  }

  String _welcome(Role r) => switch (r) {
    Role.customer => 'Find a salon near you and book in a few taps.',
    Role.salonOwner => 'Set up your salon, services and team. HOLA verifies new salons before customers can book.',
    Role.salesOfficer => 'Review new salons, plan visits and take trade orders.',
    Role.rider => 'Deliveries assigned to you will appear here.',
    Role.salonStaff => 'Your appointments and schedule live here.',
    Role.trainer => 'Your training sessions, enrolments and attendance live here.',
  };

  @override
  Future<void> signOut() async {
    // Fingerprint sign-in on: keep the session for the next fingerprint.
    final id = me?.id;
    if (api != null && id != null && fingerprintOn(id)) {
      await api!.parkSession(id);
      _parked.add(id);
    } else {
      await api?.logout();
    }
    // With HOLA, the phone keeps nothing of this account (customers' names
    // and phones, bookings, orders, money, chats): the next account on this
    // phone starts clean. On-device mode keeps its local accounts.
    if (api != null) return db.wipeAccountData();
    db.sessionAccountId = null;
    db.commit();
    await db.flush();
  }

  @override
  Future<void> updateProfile({required String name, required String phone, required String city}) async {
    if (api != null) {
      final a = requireMe;
      if (name.trim().length < 2) throw DomainError(tr('Enter your full name.'), field: 'name');
      if (phone.trim().isNotEmpty) validatePhone(phone);
      try {
        final cur = await api!.get('/me') as J;
        // Changed on another phone or the portal since this one last synced:
        // don't overwrite it; show HOLA's copy and let the person check it.
        String digits(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'\D'), '');
        if ('${cur['fullName'] ?? ''}' != a.name || digits(cur['phone']) != digits(a.phone)) {
          a
            ..name = cur['fullName'] as String? ?? a.name
            ..phone = cur['phone'] as String? ?? '';
          db.commit();
          throw DomainError(tr('Your profile was changed on another device. Check it and save again.'));
        }
        final me2 = await api!.patch('/me', {'fullName': name.trim(), 'phone': phone.trim().isEmpty ? null : _apiPhone(phone), 'version': cur['version']}) as J;
        a
          ..name = me2['fullName'] as String? ?? name.trim()
          ..phone = me2['phone'] as String? ?? ''
          ..city = city.trim();
        db.commit();
      } catch (e) {
        throw apiToDomain(e, fieldNames: _fields);
      }
      return;
    }
    final a = requireMe;
    if (name.trim().length < 2) throw DomainError(tr('Enter your full name.'), field: 'name');
    validatePhone(phone);
    a
      ..name = name.trim()
      ..phone = phone.trim()
      ..city = city.trim();
    db.commit();
  }

  @override
  Future<void> changePassword(String current, String next) async {
    if (api != null) {
      validatePassword(next);
      try {
        await api!.post('/me/password', {'currentPassword': current, 'newPassword': next});
      } on ApiError catch (e) {
        if (e.code == 'INVALID_CREDENTIALS' || e.fields.containsKey('currentPassword')) throw DomainError(tr('Your current password is incorrect.'), field: 'current');
        throw apiToDomain(e, fieldNames: const {'newPassword': 'password'});
      }
      return;
    }
    final a = requireMe;
    if (hashPassword(current, a.salt) != a.passwordHash) throw DomainError(tr('Your current password is incorrect.'), field: 'current');
    validatePassword(next);
    a.salt = db.newSalt();
    a.passwordHash = hashPassword(next, a.salt);
    db.commit();
  }

  @override
  Future<void> resetPassword({required String email, required String phone, required String newPassword}) async {
    if (api != null) throw DomainError(tr('Use the reset link HOLA emails you.'));
    final a = _byEmail(email);
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (a == null || a.role == Role.salonStaff || a.phone.replaceAll(RegExp(r'[^0-9]'), '') != digits) throw DomainError(tr("That email and phone number don't match an account."), field: 'phone');
    validatePassword(newPassword);
    a.salt = db.newSalt();
    a.passwordHash = hashPassword(newPassword, a.salt);
    db.commit();
  }

  @override
  Future<void> deleteAccount(String password) async {
    final a = requireMe;
    if (api != null) {
      if (a.role != Role.customer) throw DomainError(tr('Ask HOLA to close this account.'));
      try {
        await api!.post('/me/delete-account', {'password': password});
      } on ApiError catch (e) {
        if (e.code == 'INVALID_CREDENTIALS' || e.status == 401 || e.fields.containsKey('password')) throw DomainError(tr('Password is incorrect.'), field: 'password');
        throw apiToDomain(e);
      }
      await api!.clearSession();
      await db.wipeAccountData();
      return;
    }
    if (hashPassword(password, a.salt) != a.passwordHash) throw DomainError(tr('Password is incorrect.'), field: 'password');
    if (a.role == Role.salonOwner && a.salonId != null) throw DomainError(tr('A salon owner account can\'t be deleted while the salon is on HOLA.'));
    // Personal data goes; bookings keep the name the salon saw.
    db.accounts.remove(a);
    db.notifications.removeWhere((n) => n.userId == a.id);
    db.staff.removeWhere((s) => s.accountId == a.id);
    db.sessionAccountId = null;
    db.commit();
    await db.flush();
  }
}

/// Creates and stores an account (used by sign-up and by owners adding staff).
Account createAccount(LocalDatabase db, {required Role role, required String name, required String email, required String phone, required String password, String city = '', String? salonId}) {
  if (name.trim().length < 2) throw DomainError(tr('Enter the full name.'), field: 'name');
  validateEmail(email);
  validatePhone(phone);
  validatePassword(password);
  if (db.accounts.any((a) => a.email == normEmail(email))) throw DomainError(tr('An account with this email already exists.'), field: 'email');
  final salt = db.newSalt();
  final a = Account(
    id: db.newId(),
    email: normEmail(email),
    name: name.trim(),
    phone: phone.trim(),
    role: role,
    passwordHash: hashPassword(password, salt),
    salt: salt,
    salonId: salonId,
    city: city.trim(),
    createdAt: now(),
  );
  db.accounts.add(a);
  return a;
}
