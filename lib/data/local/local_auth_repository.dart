import 'package:flutter/foundation.dart';

import '../../core/l10n/l10n.dart';
import '../../core/security/sha256.dart';
import '../../core/utils/clock.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import 'local_database.dart';

/// Shared plumbing for the on-device repositories.
abstract class LocalRepository implements Observable {
  LocalRepository(this.db);
  final LocalDatabase db;

  @override
  Listenable get changes => db;

  Account? get me => db.sessionAccountId == null ? null : db.accounts.where((a) => a.id == db.sessionAccountId).firstOrNull;
  Account get requireMe => me ?? (throw DomainError(tr('Please sign in again.')));

  /// Salon the signed-in owner or staff member works at.
  Salon get mySalon {
    final id = requireMe.salonId;
    return db.salons.where((s) => s.id == id).firstOrNull ?? (throw DomainError(tr('Set up your salon first.')));
  }

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
  LocalAuthRepository(super.db);

  @override
  Future<void> init() => db.load();

  @override
  Account? get current => me;

  @override
  Account? account(String id) => db.accounts.where((a) => a.id == id).firstOrNull;

  @override
  List<Account> accountsWithRole(Role role) => db.accounts.where((a) => a.role == role).toList();

  Account? _byEmail(String email) => db.accounts.where((a) => a.email == normEmail(email)).firstOrNull;

  @override
  Future<Account> signIn(String email, String password) async {
    final a = _byEmail(email);
    if (a == null || hashPassword(password, a.salt) != a.passwordHash) throw DomainError(tr('Email or password is incorrect.'), field: 'password');
    db.sessionAccountId = a.id;
    db.commit();
    return a;
  }

  @override
  Future<Account> signUp({required Role role, required String name, required String email, required String phone, required String password, String city = ''}) async {
    if (!Role.signUp.contains(role)) throw DomainError(tr('Salon staff accounts are created by their salon.'));
    final a = createAccount(db, role: role, name: name, email: email, phone: phone, password: password, city: city);
    db.sessionAccountId = a.id;
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
      };

  @override
  Future<void> signOut() async {
    db.sessionAccountId = null;
    db.commit();
    await db.flush();
  }

  @override
  Future<void> updateProfile({required String name, required String phone, required String city}) async {
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
    final a = requireMe;
    if (hashPassword(current, a.salt) != a.passwordHash) throw DomainError(tr('Your current password is incorrect.'), field: 'current');
    validatePassword(next);
    a.salt = db.newSalt();
    a.passwordHash = hashPassword(next, a.salt);
    db.commit();
  }

  @override
  Future<void> resetPassword({required String email, required String phone, required String newPassword}) async {
    final a = _byEmail(email);
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (a == null || a.phone.replaceAll(RegExp(r'[^0-9]'), '') != digits) throw DomainError(tr("That email and phone number don't match an account."), field: 'phone');
    validatePassword(newPassword);
    a.salt = db.newSalt();
    a.passwordHash = hashPassword(newPassword, a.salt);
    db.commit();
  }

  @override
  Future<void> deleteAccount(String password) async {
    final a = requireMe;
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
