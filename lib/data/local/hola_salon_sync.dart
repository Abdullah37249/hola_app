import '../../core/l10n/l10n.dart';
import '../../core/network/api.dart';
import '../../domain/repositories/repositories.dart' show DomainError;
import '../../core/utils/clock.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/json.dart' show asInt;
import 'hola_mirror.dart';
import 'local_database.dart';

/// Salon set-up for a HOLA-server salon: opening hours, the team and the menu
/// are written to the server, then read back, so customers see exactly what
/// the salon set.
class HolaSalonSync {
  HolaSalonSync(this.db, this.api);
  final LocalDatabase db;
  final HolaApi api;

  /// Server versions of team members, needed to edit them.
  final _memberVersion = <String, int>{};

  static List _list(Object? res) => res is Map ? (res['data'] as List? ?? const []) : (res as List? ?? const []);
  static String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  static int _mins(String t) => int.parse(t.split(':')[0]) * 60 + int.parse(t.split(':')[1]);

  /// Local index 0 = Monday; server weekday 0 = Sunday.
  static int _serverDay(int local) => (local + 1) % 7;
  static int _localDay(int server) => (server + 6) % 7;

  // ── hours ──

  Future<void> pushHours(Branch b) async {
    await api.put('/salons/${b.salonId}/branches/${b.id}/hours', {
      'days': [
        for (var server = 0; server < 7; server++)
          if (b.hours[_localDay(server)] case final h?)
            {'weekday': server, 'closed': false, 'opens': _hm(h.start), 'closes': h.end >= 24 * 60 ? '24:00' : _hm(h.end)}
          else
            {'weekday': server, 'closed': true},
      ],
    });
  }

  // ── team ──

  /// Reads the team from the server: names, titles, who takes bookings and
  /// their weekly hours. Local team records for this salon are replaced.
  Future<void> pullTeam(String salonId) async {
    final members = _list(await api.get('/salons/$salonId/staff')).cast<J>();
    final keep = <String>{};
    for (final m in members) {
      if (m['active'] == false) continue;
      final id = m['id'] as String;
      keep.add(id);
      _memberVersion[id] = asInt(m['version']);
      mirrorPerson(db, id, m['fullName'] as String? ?? '', salonId: salonId, phone: m['phone'] as String? ?? '');
      final week = List<Shift?>.filled(7, null);
      String? branchOf;
      try {
        final sch = await api.get('/salons/$salonId/staff/$id/schedule');
        final shifts = sch is Map ? (sch['shifts'] as List? ?? const []) : (sch as List? ?? const []);
        for (final s in shifts.cast<J>()) {
          week[_localDay(asInt(s['weekday']))] = Shift(_mins(s['start'] as String), _mins(s['end'] as String));
          branchOf ??= s['branchId'] as String?;
        }
      } catch (_) {}
      final p = db.staff.where((x) => x.accountId == id).firstOrNull;
      if (p == null) {
        db.staff.add(StaffProfile(accountId: id, salonId: salonId, title: m['title'] as String? ?? '', bookable: m['bookable'] == true, week: week, createdAt: now(), branchId: branchOf));
      } else {
        p
          ..title = m['title'] as String? ?? p.title
          ..bookable = m['bookable'] == true
          ..branchId = branchOf ?? p.branchId;
        p.week.setAll(0, week);
      }
    }
    db.staff.removeWhere((p) => p.salonId == salonId && !keep.contains(p.accountId));
  }

  /// Saves a member's title, whether they take bookings, and weekly hours.
  Future<void> pushMember(String salonId, String memberId, {required String title, required bool bookable, required List<Shift?> week, String? atBranch}) async {
    if (bookable && week.every((d) => d == null)) {
      throw DomainError(tr('Turn on at least one working day, or switch off “Takes bookings”.'));
    }
    // Their shifts are at the branch they work at (the first branch by default).
    final branchId = atBranch ?? db.branches.where((b) => b.salonId == salonId && !b.id.endsWith('~delivery')).firstOrNull?.id;
    // Always edit the latest version: the server rejects a stale one.
    final members = _list(await api.get('/salons/$salonId/staff')).cast<J>();
    final cur = members.where((m) => m['id'] == memberId).firstOrNull;
    final res = await api.patch('/salons/$salonId/staff/$memberId', {
      if (title.trim().isNotEmpty) 'title': title.trim(),
      'bookable': bookable,
      'version': asInt(cur?['version'], _memberVersion[memberId] ?? 1),
    });
    if (res is Map && res['version'] != null) _memberVersion[memberId] = asInt(res['version']);
    if (branchId != null) {
      await api.put('/salons/$salonId/staff/$memberId/schedule', {
        'shifts': [
          for (var local = 0; local < 7; local++)
            if (week[local] case final h?) {'branchId': branchId, 'weekday': _serverDay(local), 'start': _hm(h.start), 'end': h.end >= 24 * 60 ? '24:00' : _hm(h.end)},
        ],
      });
    }
  }

  /// Adds a team member by name (no login, as the salon owner decided) who
  /// works the salon's opening hours and takes bookings straight away.
  /// Returns their member id.
  Future<String> addMember(String salonId, {required String name, String phone = '', String title = ''}) async {
    final res =
        await api.post('/salons/$salonId/staff', {
              'fullName': name.trim(),
              if (phone.trim().isNotEmpty) 'phone': phone.replaceAll(RegExp(r'[^0-9+]'), ''),
              if (title.trim().isNotEmpty) 'title': title.trim(),
              'bookable': true,
            })
            as J;
    final id = res['id'] as String;
    _memberVersion[id] = asInt(res['version'], 1);
    final branchId = db.branches.where((b) => b.salonId == salonId && !b.id.endsWith('~delivery')).firstOrNull?.id;
    final week = _openingWeek(salonId);
    if (branchId != null) {
      await api.put('/salons/$salonId/staff/$id/schedule', {
        'shifts': [
          for (var local = 0; local < 7; local++)
            if (week[local] case final h?) {'branchId': branchId, 'weekday': _serverDay(local), 'start': _hm(h.start), 'end': h.end >= 24 * 60 ? '24:00' : _hm(h.end)},
        ],
      });
    }
    return id;
  }

  /// A new salon's owner is its first stylist: make them bookable for the
  /// opening hours, so customers can book as soon as the menu has a service.
  Future<void> ensureOwnerBookable(String salonId, String ownerUserId) async {
    final members = _list(await api.get('/salons/$salonId/staff')).cast<J>();
    final me = members.where((m) => m['userId'] == ownerUserId).firstOrNull;
    if (me == null) return;
    final id = me['id'] as String;
    if (me['bookable'] == true && (await _shifts(salonId, id)).isNotEmpty) return;
    // A stylist with no working hours never shows to customers: give the owner
    // the salon's opening hours, or a normal week if none are set yet.
    await pushMember(salonId, id, title: me['title'] as String? ?? 'Owner', bookable: true, week: _openingWeek(salonId));
  }

  /// The salon's opening hours as a working week (Mon–Sat 10:00–20:00 if unset).
  List<Shift?> _openingWeek(String salonId) {
    final b = db.branches.where((x) => x.salonId == salonId).firstOrNull;
    if (b != null && b.hours.any((h) => h != null)) return [...b.hours];
    return [for (var i = 0; i < 7; i++) i == 6 ? null : const Shift(10 * 60, 20 * 60)];
  }

  Future<List> _shifts(String salonId, String memberId) async {
    try {
      final sch = await api.get('/salons/$salonId/staff/$memberId/schedule');
      return sch is Map ? (sch['shifts'] as List? ?? const []) : (sch as List? ?? const []);
    } catch (_) {
      return const [];
    }
  }

  /// After opening hours change: any bookable stylist with no working hours
  /// on the server gets the new opening hours, so customers can book them.
  Future<void> fillEmptySchedules(String salonId) async {
    final members = _list(await api.get('/salons/$salonId/staff')).cast<J>();
    for (final m in members.where((m) => m['bookable'] == true && m['active'] != false)) {
      final id = m['id'] as String;
      if ((await _shifts(salonId, id)).isEmpty) {
        await pushMember(salonId, id, title: m['title'] as String? ?? '', bookable: true, week: _openingWeek(salonId));
      }
    }
  }

  // ── menu ──

  /// Adds a service to every branch's menu: HOLA's own catalogue service
  /// when the name matches one, otherwise the salon's own service.
  Future<void> addService(String salonId, {required String name, required String category, String description = '', required int price, required int durationMin}) async {
    final catalogue = _list(await api.get('/services', auth: false)).cast<J>();
    final match = catalogue.where((s) => (s['name'] as String? ?? '').trim().toLowerCase() == name.trim().toLowerCase()).firstOrNull;
    final body = match != null
        ? {'serviceId': match['id'], 'price': '$price', 'durationMin': durationMin}
        : {'name': name.trim(), 'category': category, if (description.trim().isNotEmpty) 'description': description.trim(), 'price': '$price', 'durationMin': durationMin};
    for (final b in db.branches.where((x) => x.salonId == salonId)) {
      await api.post('/salons/$salonId/branches/${b.id}/services', body);
    }
  }

  /// The menu item's version, and whether it's the salon's own service.
  Future<(int, bool)> _item(String salonId, String itemId) async {
    for (final b in db.branches.where((x) => x.salonId == salonId)) {
      final items = _list(await api.get('/salons/$salonId/branches/${b.id}/services')).cast<J>();
      final it = items.where((x) => x['id'] == itemId).firstOrNull;
      if (it != null) return (asInt(it['version'], 1), (it['service'] as Map?)?['custom'] == true);
    }
    return (1, false);
  }

  Future<void> updateService(String salonId, String itemId, {String? name, String? category, String? description, int? price, int? durationMin, bool? active}) async {
    final (version, custom) = await _item(salonId, itemId);
    await api.patch('/salons/$salonId/branch-services/$itemId', {
      // Only the salon's own services can be renamed or re-described.
      if (custom) ...{'name': ?name?.trim(), 'category': ?category, if (description != null) 'description': description.trim()},
      if (price != null) 'price': '$price',
      'durationMin': ?durationMin,
      'active': ?active,
      'version': version,
    });
  }

  Future<void> deleteService(String salonId, String itemId) => api.delete('/salons/$salonId/branch-services/$itemId');

  /// Reads the live menu, branches and hours back from the directory.
  Future<void> pullSalon(String salonId, {String ownerId = ''}) async {
    await mirrorDiscoverSalon(db, api, await api.get('/discover/salons/$salonId', auth: false) as J, ownerId: ownerId);
  }

  // ── leave (time off) ──

  /// HOLA keeps leave as start/end instants; the phone shows whole days.
  /// A day off runs from local midnight to the next midnight.
  LeaveRequest _leave(String salonId, J j) {
    final s = DateTime.parse('${j['startsAt']}').toLocal();
    final e = DateTime.parse('${j['endsAt']}').toLocal().subtract(const Duration(minutes: 1));
    final st = '${j['status'] ?? 'REQUESTED'}';
    return LeaveRequest(
      id: '${j['id']}',
      salonId: salonId,
      staffId: '${(j['member'] as Map?)?['id'] ?? j['memberId'] ?? ''}',
      from: DateTime(s.year, s.month, s.day),
      to: DateTime(e.year, e.month, e.day),
      reason: '${j['reason'] ?? ''}',
      status: st == 'REQUESTED' ? 'PENDING' : st,
      createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal() ?? now(),
    );
  }

  void _keepLeave(LeaveRequest l) {
    final i = db.leave.indexWhere((x) => x.id == l.id);
    i < 0 ? db.leave.add(l) : db.leave[i] = l;
  }

  /// Every leave request of the salon (managers see the whole team).
  Future<void> pullLeave(String salonId) async {
    final list = _list(await api.get('/salons/$salonId/leave')).cast<J>();
    final seen = <String>{};
    for (final j in list) {
      final l = _leave(salonId, j);
      seen.add(l.id);
      _keepLeave(l);
    }
    db.leave.removeWhere((l) => l.salonId == salonId && !seen.contains(l.id));
  }

  /// A manager recording leave for a team member: approved straight away.
  Future<LeaveRequest> addLeave(String salonId, {required String memberId, required DateTime from, required DateTime to, required String reason}) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day + 1);
    final j =
        await api.post('/salons/$salonId/leave', {
              'memberId': memberId,
              'startsAt': start.toUtc().toIso8601String(),
              'endsAt': end.toUtc().toIso8601String(),
              if (reason.trim().isNotEmpty) 'reason': reason.trim(),
            })
            as J;
    final l = _leave(salonId, j);
    _keepLeave(l);
    return l;
  }

  /// approve | decline | cancel
  Future<void> leaveAction(String salonId, String leaveId, String action) async {
    _keepLeave(_leave(salonId, await api.post('/salons/$salonId/leave/$leaveId/$action', const {}) as J));
  }

  // ── booking policy ──

  /// Auto-confirm, cancellation window, no-show grace and the check-in window
  /// as HOLA applies them (its defaults fill in what the salon hasn't set).
  Future<void> pullPolicy(String salonId) async {
    final j = await api.get('/salons/$salonId/booking-policy') as J;
    final s = db.salons.where((x) => x.id == salonId).firstOrNull;
    if (s == null) return;
    final e = j['effective'] as Map? ?? const {};
    s
      ..autoConfirm = j['autoConfirm'] == true
      ..cancelWindowHours = (asInt(e['cancellationWindowMin'] ?? j['cancellationWindowMin'], 120) / 60).round()
      ..noShowGraceMin = asInt(e['noShowGraceMin'] ?? j['noShowGraceMin'], 15)
      ..checkInEarlyMin = asInt(e['checkInEarlyMin'], 60);
  }

  Future<void> updatePolicy(String salonId, {required bool autoConfirm, required int cancelWindowHours, required int noShowGraceMin}) async {
    final cur = await api.get('/salons/$salonId/booking-policy') as J;
    await api.patch('/salons/$salonId/booking-policy', {'autoConfirm': autoConfirm, 'cancellationWindowMin': cancelWindowHours * 60, 'noShowGraceMin': noShowGraceMin, 'version': cur['version']});
    await pullPolicy(salonId);
  }

  // ── profile, branch, photos ──

  Future<void> updateProfile(String salonId, {String? name, String? phone, String? description, bool? autoConfirm}) async {
    final cur = await api.get('/salons/$salonId') as J;
    await api.patch('/salons/$salonId', {
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (phone != null) 'phone': phone.trim().isEmpty ? null : phone.replaceAll(RegExp(r'[^0-9+]'), ''),
      if (description != null) 'description': description.trim(),
      'autoConfirm': ?autoConfirm,
      'version': cur['version'],
    });
  }

  Future<void> updateBranch(Branch b, {required String name, required String address, required String area, required String city}) async {
    final list = _list(await api.get('/salons/${b.salonId}/branches')).cast<J>();
    final cur = list.where((x) => x['id'] == b.id).firstOrNull;
    // Send only what's filled in: the server rejects empty text.
    await api.patch('/salons/${b.salonId}/branches/${b.id}', {
      if (name.trim().isNotEmpty) 'name': name.trim(),
      if (address.trim().isNotEmpty) 'addressLine': address.trim(),
      if (area.trim().isNotEmpty) 'area': area.trim(),
      if (city.trim().isNotEmpty) 'city': city.trim(),
      'version': cur?['version'] ?? 1,
    });
  }

  /// Opens a new branch on HOLA with the main branch's opening hours and
  /// menu, so customers can book it once someone on the team works there.
  /// Returns the new branch.
  Future<Branch> addBranch(String salonId, {required String name, required String address, required String area, required String city}) async {
    final res = await api.post('/salons/$salonId/branches', {'name': name.trim(), 'addressLine': address.trim(), if (area.trim().isNotEmpty) 'area': area.trim(), 'city': city.trim()}) as J;
    final main = db.branches.where((b) => b.salonId == salonId && !b.id.endsWith('~delivery')).firstOrNull;
    final b = Branch(
      id: res['id'] as String,
      salonId: salonId,
      name: res['name'] as String? ?? name.trim(),
      address: res['addressLine'] as String? ?? address.trim(),
      area: res['area'] as String? ?? area.trim(),
      city: res['city'] as String? ?? city.trim(),
      hours: main == null ? null : [...main.hours],
    );
    db.branches.add(b);
    if (main != null) {
      await pushHours(b);
      // The same services and prices as the main branch.
      final items = _list(await api.get('/salons/$salonId/branches/${main.id}/services')).cast<J>();
      for (final it in items.where((x) => x['active'] != false)) {
        // Linked by service id (HOLA's or the salon's own), at the same price and length.
        final svcId = (it['service'] as Map?)?['id'];
        if (svcId == null) continue;
        await api.post('/salons/$salonId/branches/${b.id}/services', {'serviceId': svcId, 'price': '${it['price']}', 'durationMin': asInt(it['durationMin'], 30)});
      }
    }
    return b;
  }

  Future<void> deleteBranch(String salonId, String branchId) => api.delete('/salons/$salonId/branches/$branchId');

  /// Saves where the branch is: HOLA's flat latitude/longitude (both together).
  Future<void> setBranchLocation(Branch b, GeoFix at) async {
    final list = _list(await api.get('/salons/${b.salonId}/branches')).cast<J>();
    final cur = list.where((x) => x['id'] == b.id).firstOrNull;
    await api.patch('/salons/${b.salonId}/branches/${b.id}', {'latitude': at.lat, 'longitude': at.lng, 'version': cur?['version'] ?? 1});
  }

  /// Sets the salon's photos in order (first = cover). Photos still on the
  /// phone are uploaded first; ones already on HOLA keep their file id.
  /// Returns the public links to show.
  Future<List<String>> setPhotos(String salonId, List<String> photos, Future<List<int>?> Function(String localName) readLocal) async {
    final ids = <String>[];
    for (final p in photos) {
      if (p.startsWith('https://')) {
        ids.add(Uri.parse(p).pathSegments.last);
      } else {
        final bytes = await readLocal(p);
        if (bytes == null) continue;
        ids.add(await api.uploadFile(bytes, contentType: 'image/jpeg', purpose: 'salon_photo', fileName: p));
      }
    }
    final res = _list(await api.put('/salons/$salonId/photos', {'fileIds': ids})).cast<J>()..sort((a, b) => asInt(a['position']).compareTo(asInt(b['position'])));
    return [for (final x in res) x['url'] as String];
  }
}
