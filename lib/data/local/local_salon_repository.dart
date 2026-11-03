import '../../core/l10n/l10n.dart';
import '../../core/security/sha256.dart';
import '../../core/utils/clock.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import 'local_auth_repository.dart';
import '../../core/network/api.dart';
import '../../domain/entities/json.dart' show asInt;
import 'hola_mirror.dart';
import 'hola_salon_sync.dart';
import '../../core/utils/photo_files.dart';

class LocalSalonRepository extends LocalRepository implements SalonRepository {
  LocalSalonRepository(super.db, {this.api});

  /// When set, HOLA's live salons are brought in by [syncDirectory], and a
  /// HOLA salon's set-up is saved on the server.
  final HolaApi? api;

  late final HolaSalonSync? _server = api == null ? null : HolaSalonSync(db, api!);

  /// The server copy of a HOLA salon, or null for an on-device salon.
  HolaSalonSync? _on(String salonId) => salon(salonId)?.hola == true ? _server : null;

  /// Runs a server write, turning its errors into messages people can read.
  Future<T> _write<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on DomainError {
      rethrow;
    } catch (e) {
      throw apiToDomain(e);
    }
  }

  // ── reads ──

  @override
  List<Salon> allSalons() => [...db.salons]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  List<Salon> discover({String query = '', String? category, String? city}) {
    final q = query.trim().toLowerCase();
    return db.salons.where((s) {
      // HOLA's live salons are listed even before their menu loads.
      if (!s.isListed || !s.hola && (services(s.id, activeOnly: true).isEmpty || staff(s.id).every((p) => !p.bookable))) return false;
      if (category != null && !categoriesOf(s.id).contains(category)) return false;
      final bs = branches(s.id);
      if (city != null && city.isNotEmpty && !bs.any((b) => b.city.toLowerCase() == city.toLowerCase())) return false;
      if (q.isEmpty) return true;
      final hay = [
        s.name,
        ...bs.expand((b) => [b.area, b.city, b.address]),
        ...services(s.id, activeOnly: true).map((x) => '${x.name} ${x.category}'),
      ].join(' ').toLowerCase();
      return q.split(RegExp(r'\s+')).every(hay.contains);
    }).toList()..sort((a, b) => rating(b.id).average.compareTo(rating(a.id).average));
  }

  @override
  Salon? salon(String id) => db.salons.where((s) => s.id == id).firstOrNull;

  @override
  Salon? salonOfOwner(String accountId) => db.salons.where((s) => s.ownerId == accountId).firstOrNull;

  @override
  List<Branch> branches(String salonId) => db.branches.where((b) => b.salonId == salonId).toList();

  @override
  Branch? branch(String id) => db.branches.where((b) => b.id == id).firstOrNull;

  @override
  List<ServiceItem> services(String salonId, {bool activeOnly = false}) =>
      db.services.where((s) => s.salonId == salonId && (!activeOnly || s.active)).toList()..sort((a, b) => serviceCategories.indexOf(a.category).compareTo(serviceCategories.indexOf(b.category)));

  @override
  ServiceItem? service(String id) => db.services.where((s) => s.id == id).firstOrNull;

  @override
  List<String> categoriesOf(String salonId) => [
    for (final c in serviceCategories)
      if (services(salonId, activeOnly: true).any((s) => s.category == c)) c,
  ];

  @override
  int fromPrice(String salonId) {
    final ps = services(salonId, activeOnly: true).map((s) => s.price);
    return ps.isEmpty ? 0 : ps.reduce((a, b) => a < b ? a : b);
  }

  @override
  SalonRating rating(String salonId) {
    final rs = db.reviews.where((r) => r.salonId == salonId).toList();
    if (rs.isEmpty) return const SalonRating(0, 0);
    return SalonRating(rs.fold<int>(0, (s, r) => s + r.stars) / rs.length, rs.length);
  }

  @override
  List<StaffProfile> staff(String salonId) => db.staff.where((s) => s.salonId == salonId && db.accounts.any((a) => a.id == s.accountId)).toList();

  @override
  StaffProfile? staffProfile(String accountId) => db.staff.where((s) => s.accountId == accountId).firstOrNull;

  @override
  List<LeaveRequest> leave(String salonId) => db.leave.where((l) => l.salonId == salonId).toList()..sort((a, b) => a.from.compareTo(b.from));

  @override
  List<LeaveRequest> leaveFor(String staffId) => db.leave.where((l) => l.staffId == staffId).toList()..sort((a, b) => b.from.compareTo(a.from));

  @override
  bool isFavourite(String salonId) => me?.favourites.contains(salonId) ?? false;

  // ── setup ──

  Salon _ownedSalon(String salonId) {
    final s = salon(salonId) ?? (throw DomainError(tr('Salon not found.')));
    final a = requireMe;
    if (s.ownerId != a.id) throw DomainError(tr('Only the salon owner can change this.'));
    return s;
  }

  void _validateName(String name, String what) {
    if (name.trim().length >= 2) return;
    final message = switch (what) {
      'salon name' => tr('Enter the salon name.'),
      'branch name' => tr('Enter the branch name.'),
      'service name' => tr('Enter the service name.'),
      'address' => tr('Enter the address.'),
      'area' => tr('Enter the area.'),
      'city' => tr('Enter the city.'),
      _ => tr('Enter the {what}.', {'what': what}),
    };
    throw DomainError(message, field: what.endsWith('name') ? 'name' : what);
  }

  @override
  Future<void> setBranchLocation(String branchId, GeoFix at) async {
    final b = db.branches.where((x) => x.id == branchId).firstOrNull ?? (throw DomainError(tr('Branch not found.')));
    if (_on(b.salonId) case final server?) await _write(() => server.setBranchLocation(b, at));
    b.location = at;
    db.commit();
  }

  @override
  Future<Salon> createSalon({
    required String name,
    required String phone,
    required String about,
    required String branchName,
    required String address,
    required String area,
    required String city,
  }) async {
    requireRole({Role.salonOwner});
    final owner = requireMe;
    if (owner.salonId != null) throw DomainError(tr('You already have a salon.'));
    _validateName(name, 'salon name');
    validatePhone(phone);
    _validateName(address, 'address');
    _validateName(area, 'area');
    _validateName(city, 'city');
    final s = Salon(id: db.newId(), ownerId: owner.id, name: name.trim(), phone: phone.trim(), about: about.trim(), palette: db.salons.length % 8, createdAt: now());
    db.salons.add(s);
    db.branches.add(Branch(id: db.newId(), salonId: s.id, name: branchName.trim().isEmpty ? area.trim() : branchName.trim(), address: address.trim(), area: area.trim(), city: city.trim()));
    owner.salonId = s.id;
    // The owner is a bookable professional by default, working the opening hours.
    db.staff.add(StaffProfile(accountId: owner.id, salonId: s.id, title: 'Owner', week: [for (var i = 0; i < 7; i++) i == 6 ? null : const Shift(10 * 60, 20 * 60)], createdAt: now()));
    db.notifyRole(
      Role.salesOfficer,
      'New salon to verify',
      '{salon} in {area}, {city} signed up.',
      args: {'salon': s.name, 'area': area.trim(), 'city': city.trim()},
      icon: 'store',
      link: NotifLink('salon', s.id),
    );
    db.commit();
    return s;
  }

  @override
  Future<void> updateSalon(String salonId, {required String name, required String phone, required String about}) async {
    final s = _ownedSalon(salonId);
    _validateName(name, 'salon name');
    validatePhone(phone);
    if (_on(salonId) case final server?) await _write(() => server.updateProfile(salonId, name: name, phone: phone, description: about));
    s
      ..name = name.trim()
      ..phone = phone.trim()
      ..about = about.trim();
    db.commit();
  }

  @override
  Future<void> setSalonPhotos(String salonId, List<String> photos) async {
    final s = _ownedSalon(salonId);
    if (photos.length > maxSalonPhotos) throw DomainError(tr('A salon can show up to {n} photos.', {'n': maxSalonPhotos}));
    if (_on(salonId) case final server?) {
      // Uploaded to HOLA so customers see them; the salon then shows the public links.
      s.photos = await _write(() => server.setPhotos(salonId, photos, (name) async => PhotoFiles.file(name)?.readAsBytes()));
      db.commit();
      return;
    }
    s.photos = List.of(photos);
    db.commit();
  }

  @override
  Future<Branch> addBranch(String salonId, {required String name, required String address, required String area, required String city}) async {
    _ownedSalon(salonId);
    _validateName(name, 'branch name');
    _validateName(address, 'address');
    _validateName(city, 'city');
    final b = Branch(id: db.newId(), salonId: salonId, name: name.trim(), address: address.trim(), area: area.trim(), city: city.trim());
    db.branches.add(b);
    db.commit();
    return b;
  }

  @override
  Future<void> updateBranch(String branchId, {required String name, required String address, required String area, required String city, required List<Shift?> hours}) async {
    final b = branch(branchId) ?? (throw DomainError(tr('Branch not found.')));
    _ownedSalon(b.salonId);
    _validateName(name, 'branch name');
    _validateName(address, 'address');
    for (final h in hours) {
      if (h != null && h.end <= h.start) throw DomainError(tr('Closing time must be after opening time.'));
    }
    if (_on(b.salonId) case final server?) {
      await _write(() => server.updateBranch(b, name: name, address: address, area: area, city: city));
      await _write(() => server.pushHours(Branch(id: b.id, salonId: b.salonId, name: b.name, address: b.address, area: b.area, city: b.city, hours: hours)));
      b.hours.setAll(0, hours);
      await _write(() => server.fillEmptySchedules(b.salonId));
      await _write(() => server.pullTeam(b.salonId));
    }
    b
      ..name = name.trim()
      ..address = address.trim()
      ..area = area.trim()
      ..city = city.trim();
    b.hours.setAll(0, hours);
    db.commit();
  }

  @override
  Future<void> deleteBranch(String branchId) async {
    final b = branch(branchId) ?? (throw DomainError(tr('Branch not found.')));
    _ownedSalon(b.salonId);
    if (branches(b.salonId).length == 1) throw DomainError(tr('A salon needs at least one branch.'));
    if (db.appointments.any((a) => a.branchId == branchId && ApptStatus.holding.contains(a.status))) throw DomainError(tr('This branch has upcoming appointments.'));
    db.branches.remove(b);
    db.commit();
  }

  @override
  Future<void> updatePolicy(String salonId, {required bool autoConfirm, required int cancelWindowHours, required int noShowGraceMin}) async {
    final s = _ownedSalon(salonId);
    if (_on(salonId) case final server?) await _write(() => server.updateProfile(salonId, autoConfirm: autoConfirm));
    s
      ..autoConfirm = autoConfirm
      ..cancelWindowHours = cancelWindowHours.clamp(0, 72)
      ..noShowGraceMin = noShowGraceMin.clamp(5, 60);
    db.commit();
  }

  // ── menu ──

  @override
  Future<ServiceItem> saveService({
    String? id,
    required String salonId,
    required String name,
    required String category,
    required String description,
    required int price,
    required int durationMin,
    bool active = true,
  }) async {
    _ownedSalon(salonId);
    _validateName(name, 'service name');
    if (!serviceCategories.contains(category)) throw DomainError(tr('Pick a category.'));
    if (price <= 0) throw DomainError(tr('Enter a price.'), field: 'price');
    if (durationMin < 5 || durationMin > 600) throw DomainError(tr('Duration must be between 5 minutes and 10 hours.'));
    final existing = id == null ? null : service(id);
    if (_on(salonId) case final server?) {
      if (existing == null) {
        await _write(() async {
          await server.addService(salonId, name: name, category: category, description: description, price: price, durationMin: durationMin);
          await server.pullSalon(salonId, ownerId: salon(salonId)!.ownerId);
        });
        db.commit();
        return services(salonId).lastWhere((x) => x.name.toLowerCase() == name.trim().toLowerCase(), orElse: () => services(salonId).last);
      }
      await _write(() => server.updateService(salonId, existing.id, name: name, category: category, description: description, price: price, durationMin: durationMin, active: active));
    }
    if (existing != null) {
      existing
        ..name = name.trim()
        ..category = category
        ..description = description.trim()
        ..price = price
        ..durationMin = durationMin
        ..active = active;
      db.commit();
      return existing;
    }
    final s = ServiceItem(id: db.newId(), salonId: salonId, name: name.trim(), category: category, description: description.trim(), price: price, durationMin: durationMin, active: active);
    db.services.add(s);
    db.commit();
    return s;
  }

  @override
  Future<void> setServiceActive(String id, bool active) async {
    final s = service(id) ?? (throw DomainError(tr('Service not found.')));
    _ownedSalon(s.salonId);
    if (_on(s.salonId) case final server?) await _write(() => server.updateService(s.salonId, id, active: active));
    s.active = active;
    db.commit();
  }

  @override
  Future<void> deleteService(String id) async {
    final s = service(id) ?? (throw DomainError(tr('Service not found.')));
    _ownedSalon(s.salonId);
    if (db.appointments.any((a) => a.serviceIds.contains(id) && ApptStatus.holding.contains(a.status))) {
      throw DomainError(tr('Upcoming appointments use this service. Hide it instead.'));
    }
    if (_on(s.salonId) case final server?) await _write(() => server.deleteService(s.salonId, id));
    db.services.remove(s);
    db.commit();
  }

  // ── team ──

  @override
  Future<Account> addStaff(String salonId, {required String name, String phone = '', required String title}) async {
    final s = _ownedSalon(salonId);
    if (name.trim().length < 2) throw DomainError(tr('Enter the full name.'), field: 'name');
    if (phone.trim().isNotEmpty) validatePhone(phone);
    if (_on(salonId) case final server?) {
      // Saved on HOLA: a name-only member (no login) customers can book.
      final id = await _write(() async {
        final id = await server.addMember(salonId, name: name, phone: phone, title: title);
        await server.pullTeam(salonId);
        return id;
      });
      db.commit();
      return db.accounts.where((a) => a.id == id).firstOrNull ?? (throw DomainError(tr('Team member not found.')));
    }
    // A record for names, hours and bookings only: no email, no usable password.
    final salt = db.newSalt();
    final a = Account(
      id: db.newId(),
      email: '',
      name: name.trim(),
      phone: phone.trim(),
      role: Role.salonStaff,
      passwordHash: hashPassword(db.newSalt(), salt),
      salt: salt,
      salonId: s.id,
      createdAt: now(),
    );
    db.accounts.add(a);
    final hours = branches(s.id).first.hours;
    db.staff.add(StaffProfile(accountId: a.id, salonId: s.id, title: title.trim().isEmpty ? 'Stylist' : title.trim(), week: [...hours], createdAt: now()));
    db.commit();
    return a;
  }

  @override
  Future<void> updateStaff(String accountId, {required String title, required bool bookable, required List<Shift?> week}) async {
    final p = staffProfile(accountId) ?? (throw DomainError(tr('Team member not found.')));
    _ownedSalon(p.salonId);
    for (final h in week) {
      if (h != null && h.end <= h.start) throw DomainError(tr('Shift end must be after its start.'));
    }
    if (_on(p.salonId) case final server?) await _write(() => server.pushMember(p.salonId, accountId, title: title, bookable: bookable, week: week));
    p
      ..title = title.trim()
      ..bookable = bookable;
    p.week.setAll(0, week);
    db.commit();
  }

  @override
  Future<void> removeStaff(String accountId) async {
    final p = staffProfile(accountId) ?? (throw DomainError(tr('Team member not found.')));
    final s = _ownedSalon(p.salonId);
    if (accountId == s.ownerId) throw DomainError(tr("The owner can't be removed."));
    if (db.appointments.any((a) => a.staffId == accountId && a.startsAt.isAfter(now()) && ApptStatus.holding.contains(a.status))) {
      throw DomainError(tr('Reassign their upcoming appointments first.'));
    }
    if (_on(p.salonId) != null) await _write(() => api!.delete('/salons/${p.salonId}/staff/$accountId'));
    db.staff.remove(p);
    db.accounts.removeWhere((a) => a.id == accountId);
    db.commit();
  }

  @override
  Future<LeaveRequest> requestLeave({required String staffId, required DateTime from, required DateTime to, required String reason}) async {
    final p = staffProfile(staffId) ?? (throw DomainError(tr('Team member not found.')));
    _ownedSalon(p.salonId);
    final f = dateOnly(from), t = dateOnly(to);
    if (t.isBefore(f)) throw DomainError(tr('The last day must be on or after the first day.'));
    if (f.isBefore(today)) throw DomainError(tr("Leave can't start in the past."));
    if (reason.trim().length < 3) throw DomainError(tr('Add a short reason.'));
    final l = LeaveRequest(id: db.newId(), salonId: p.salonId, staffId: staffId, from: f, to: t, reason: reason.trim(), status: 'APPROVED', createdAt: now());
    db.leave.add(l);
    db.commit();
    return l;
  }

  @override
  Future<void> decideLeave(String leaveId, {required bool approve}) async {
    final l = db.leave.where((x) => x.id == leaveId).firstOrNull ?? (throw DomainError(tr('Request not found.')));
    _ownedSalon(l.salonId);
    if (l.status != 'PENDING') throw DomainError(tr('This request was already answered.'));
    l.status = approve ? 'APPROVED' : 'DECLINED';
    db.commit();
  }

  @override
  Future<void> cancelLeave(String leaveId) async {
    final l = db.leave.where((x) => x.id == leaveId).firstOrNull ?? (throw DomainError(tr('Request not found.')));
    _ownedSalon(l.salonId);
    l.status = 'CANCELLED';
    db.commit();
  }

  // ── HOLA directory ──

  Future<void>? _syncing;

  @override
  Future<void> syncDirectory() => api == null ? Future.value() : (_syncing ??= _sync().whenComplete(() => _syncing = null));

  Future<void> _sync() async {
    final live = <String>{};
    try {
      for (var page = 1, pages = 1; page <= pages; page++) {
        final res = await api!.get('/discover/salons', query: {'page': '$page', 'pageSize': '100'}, auth: false) as J;
        pages = asInt((res['meta'] as Map?)?['totalPages'], 1);
        for (final j in (res['data'] as List).cast<J>()) {
          live.add(j['id'] as String);
          await mirrorDiscoverSalon(db, api!, j);
        }
      }
      // Salons HOLA no longer lists leave the directory (bookings keep their names).
      for (final s in db.salons.where((s) => s.hola && !live.contains(s.id) && s.ownerId != me?.id)) {
        s.status = SalonStatus.suspended;
      }
      db.commit();
    } catch (e) {
      // Offline or server trouble: keep what we had; the offline banner explains.
      db.commit();
    }
  }

  // ── customers ──

  @override
  Future<bool> toggleFavourite(String salonId) async {
    final a = requireMe;
    final on = !a.favourites.contains(salonId);
    // HOLA salons are saved on the HOLA account, so they follow you to any phone.
    if (api != null && salon(salonId)?.hola == true) {
      try {
        on ? await api!.put('/me/favourites/$salonId') : await api!.delete('/me/favourites/$salonId');
      } catch (e) {
        throw apiToDomain(e);
      }
    }
    on ? a.favourites.add(salonId) : a.favourites.remove(salonId);
    db.commit();
    return on;
  }

  // ── HOLA verification ──

  Salon _forOfficer(String salonId) {
    requireRole({Role.salesOfficer});
    return salon(salonId) ?? (throw DomainError(tr('Salon not found.')));
  }

  @override
  Future<void> approveSalon(String salonId) async {
    final s = _forOfficer(salonId);
    if (services(s.id).isEmpty) throw DomainError(tr('The salon has no services yet. Ask the owner to add their menu first.'));
    s
      ..status = SalonStatus.active
      ..statusNote = null;
    db.notify(s.ownerId, 'Your salon is live', 'HOLA verified {salon}. Customers can now find and book you.', args: {'salon': s.name}, icon: 'check', link: NotifLink('salon', s.id));
    db.commit();
  }

  @override
  Future<void> requestChanges(String salonId, String note) async {
    final s = _forOfficer(salonId);
    if (note.trim().length < 5) throw DomainError(tr('Tell the owner what to change.'));
    s
      ..status = SalonStatus.changes
      ..statusNote = note.trim();
    db.notify(s.ownerId, 'Changes requested', '{note}', args: {'note': note.trim()}, icon: 'alert', link: NotifLink('salon', s.id));
    db.commit();
  }

  @override
  Future<void> suspendSalon(String salonId, String note) async {
    final s = _forOfficer(salonId);
    if (note.trim().length < 5) throw DomainError(tr('Add the reason for suspending.'));
    s
      ..status = SalonStatus.suspended
      ..statusNote = note.trim();
    db.notify(s.ownerId, 'Salon suspended', '{note}', args: {'note': note.trim()}, icon: 'alert', link: NotifLink('salon', s.id));
    db.commit();
  }

  @override
  Future<void> reactivateSalon(String salonId) async {
    final s = _forOfficer(salonId);
    s
      ..status = SalonStatus.active
      ..statusNote = null;
    db.notify(s.ownerId, 'Salon reactivated', '{salon} is visible to customers again.', args: {'salon': s.name}, icon: 'check', link: NotifLink('salon', s.id));
    db.commit();
  }

  @override
  Future<void> resubmitSalon(String salonId) async {
    final s = _ownedSalon(salonId);
    if (s.status != SalonStatus.changes) throw DomainError(tr('Nothing to resubmit.'));
    s.status = SalonStatus.pending;
    db.notifyRole(Role.salesOfficer, 'Salon resubmitted', '{salon} made the requested changes.', args: {'salon': s.name}, icon: 'store', link: NotifLink('salon', s.id));
    db.commit();
  }
}
