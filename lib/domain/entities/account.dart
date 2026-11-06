import '../../core/l10n/l10n.dart';
import 'json.dart';

/// Who a person is in the HOLA ecosystem. Decides which experience they see.
enum Role {
  customer,
  salonOwner,
  salonStaff,
  salesOfficer,
  rider,

  /// HOLA Academy trainer: runs training sessions (training.manage).
  trainer;

  /// Display name in the app language.
  String get label => switch (this) {
    customer => tr('Customer'),
    salonOwner => tr('Salon'),
    salonStaff => tr('Salon staff'),
    salesOfficer => tr('Sales officer'),
    rider => tr('Delivery rider'),
    trainer => tr('HOLA trainer'),
  };

  /// Roles a person can pick when signing up. Sales officers and riders get
  /// their accounts from HOLA and only sign in; salon team members are added
  /// by their salon and don't sign in.
  static const signUp = [customer, salonOwner];
}

class Account {
  final String id;
  String email, name, phone;
  final Role role;
  String passwordHash, salt;
  String? salonId; // owner and staff
  String city;
  final DateTime createdAt;
  final List<String> favourites; // salon ids (customers)

  Account({
    required this.id,
    required this.email,
    required this.name,
    required this.phone,
    required this.role,
    required this.passwordHash,
    required this.salt,
    this.salonId,
    this.city = '',
    required this.createdAt,
    List<String>? favourites,
  }) : favourites = favourites ?? [];

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  Json toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'phone': phone,
    'role': role.name,
    'passwordHash': passwordHash,
    'salt': salt,
    'salonId': salonId,
    'city': city,
    'createdAt': iso(createdAt),
    'favourites': favourites,
  };

  factory Account.fromJson(Json j) => Account(
    id: j['id'],
    email: j['email'],
    name: j['name'],
    phone: j['phone'] ?? '',
    role: Role.values.byName(j['role']),
    passwordHash: j['passwordHash'],
    salt: j['salt'],
    salonId: j['salonId'],
    city: j['city'] ?? '',
    createdAt: dt(j['createdAt'])!,
    favourites: strs(j['favourites']),
  );
}

/// A working window on one weekday, minutes from midnight.
class Shift {
  final int start, end;
  const Shift(this.start, this.end);
  int get minutes => end - start;
  Json toJson() => {'start': start, 'end': end};
  factory Shift.fromJson(Json j) => Shift(asInt(j['start']), asInt(j['end']));
}

/// A bookable professional at a salon (owner or staff account).
class StaffProfile {
  final String accountId, salonId;
  String title;
  bool bookable;

  /// Weekly shifts indexed by weekday 1 (Mon) .. 7 (Sun); null = day off.
  final List<Shift?> week;
  final DateTime createdAt;

  /// The branch they work at (null = the salon's first branch).
  String? branchId;

  StaffProfile({required this.accountId, required this.salonId, required this.title, this.bookable = true, List<Shift?>? week, required this.createdAt, this.branchId})
    : week = week ?? List<Shift?>.filled(7, null);

  Shift? shiftOn(DateTime d) => week[d.weekday - 1];

  Json toJson() => {
    'accountId': accountId,
    'salonId': salonId,
    'title': title,
    'bookable': bookable,
    'week': [for (final s in week) s?.toJson()],
    'createdAt': iso(createdAt),
    if (branchId != null) 'branchId': branchId,
  };

  factory StaffProfile.fromJson(Json j) => StaffProfile(
    accountId: j['accountId'],
    salonId: j['salonId'],
    title: j['title'] ?? '',
    bookable: j['bookable'] ?? true,
    week: [for (final s in (j['week'] as List)) s == null ? null : Shift.fromJson(s as Json)],
    createdAt: dt(j['createdAt'])!,
    branchId: j['branchId'],
  );
}

class LeaveRequest {
  final String id, salonId, staffId;
  final DateTime from, to; // inclusive dates
  final String reason;
  String status; // PENDING | APPROVED | DECLINED | CANCELLED
  final DateTime createdAt;

  LeaveRequest({required this.id, required this.salonId, required this.staffId, required this.from, required this.to, required this.reason, this.status = 'PENDING', required this.createdAt});

  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  Json toJson() => {'id': id, 'salonId': salonId, 'staffId': staffId, 'from': iso(from), 'to': iso(to), 'reason': reason, 'status': status, 'createdAt': iso(createdAt)};
  factory LeaveRequest.fromJson(Json j) =>
      LeaveRequest(id: j['id'], salonId: j['salonId'], staffId: j['staffId'], from: dt(j['from'])!, to: dt(j['to'])!, reason: j['reason'] ?? '', status: j['status'], createdAt: dt(j['createdAt'])!);
}

/// An account that signs in with a fingerprint on this phone.
class FingerprintAccount {
  final String accountId, name, email;

  /// Role name (e.g. 'rider'), so each sign-in screen offers its own accounts.
  final String role;
  const FingerprintAccount({required this.accountId, required this.name, required this.email, this.role = ''});
  String get firstName => name.trim().split(' ').first;
  Map<String, dynamic> toJson() => {'accountId': accountId, 'name': name, 'email': email, 'role': role};
  factory FingerprintAccount.fromJson(Map<String, dynamic> j) =>
      FingerprintAccount(accountId: '${j['accountId']}', name: '${j['name'] ?? ''}', email: '${j['email'] ?? ''}', role: '${j['role'] ?? ''}');
}
