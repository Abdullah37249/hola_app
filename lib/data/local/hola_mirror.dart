import '../../core/network/api.dart';
import '../../core/utils/clock.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/json.dart' show asInt;
import 'local_database.dart';

// Copies HOLA server records into the on-device database, so the screens
// (which read the device database) show them. The server stays the source of
// truth: these copies are refreshed from it and never edited on the phone.

/// "10:30" → minutes after midnight.
int _mins(String t) => int.parse(t.split(':')[0]) * 60 + int.parse(t.split(':')[1]);

/// "2500.00" → 2500 rupees.
int money(Object? v) => double.tryParse('$v')?.round() ?? 0;

/// A person the server knows (stylist, customer) shown by name on the phone.
/// They can't sign in with this copy: it has no email or password.
Account mirrorPerson(LocalDatabase db, String id, String name, {Role role = Role.salonStaff, String? salonId, String phone = ''}) {
  final a = db.accounts.where((x) => x.id == id).firstOrNull;
  if (a != null) {
    if (name.isNotEmpty) a.name = name;
    return a;
  }
  final n = Account(id: id, email: '', name: name, phone: phone, role: role, passwordHash: '', salt: '', salonId: salonId, createdAt: now());
  db.accounts.add(n);
  return n;
}

/// Upserts one salon from GET /discover/salons (or /discover/salons/{id}),
/// with branches, opening hours and, via [api], each branch's menu and stylists.
Future<Salon> mirrorDiscoverSalon(LocalDatabase db, HolaApi api, J j, {String ownerId = ''}) async {
  final id = j['id'] as String;
  var s = db.salons.where((x) => x.id == id).firstOrNull;
  if (s == null) {
    s = Salon(
      id: id,
      ownerId: ownerId,
      name: j['name'] as String? ?? '',
      phone: '',
      about: j['description'] as String? ?? '',
      status: SalonStatus.active,
      palette: id.hashCode.abs() % 6,
      hola: true,
      createdAt: now(),
    );
    db.salons.add(s);
  } else {
    s
      ..name = j['name'] as String? ?? s.name
      ..about = j['description'] as String? ?? s.about
      ..status = SalonStatus.active;
  }
  // Photos are public links (first = cover); fall back to the cover link alone.
  final photos = [
    for (final p in (j['photos'] as List? ?? const []).cast<Map>())
      if (p['url'] is String) p['url'] as String,
  ];
  s.photos = photos.isNotEmpty ? photos : [if (j['coverUrl'] is String) j['coverUrl'] as String];
  // Published reviews only (contract 0.18.0).
  if (j.containsKey('ratingCount')) {
    s.ratingCount = asInt(j['ratingCount']);
    s.ratingAverage = double.tryParse('${j['ratingAverage'] ?? ''}');
  }
  final onMenu = <String>{};
  var menusLoaded = true;
  final liveBranches = <String>{};
  for (final b in (j['branches'] as List? ?? const []).cast<J>()) {
    final bid = b['id'] as String;
    liveBranches.add(bid);
    final hours = List<Shift?>.filled(7, null);
    for (final h in (b['hours'] as List? ?? const []).cast<J>()) {
      if (h['closed'] == true || h['opens'] == null || h['closes'] == null) continue;
      hours[(asInt(h['weekday']) + 6) % 7] = Shift(_mins(h['opens'] as String), _mins(h['closes'] as String)); // server 0 = Sunday; here 0 = Monday
    }
    final nb = Branch(
      id: bid,
      salonId: id,
      name: b['name'] as String? ?? '',
      address: b['addressLine'] as String? ?? '',
      area: b['area'] as String? ?? '',
      city: b['city'] as String? ?? '',
      hours: hours,
    );
    final i = db.branches.indexWhere((x) => x.id == bid);
    nb.location = branchGeo(b) ?? (i < 0 ? null : db.branches[i].location);
    i < 0 ? db.branches.add(nb) : db.branches[i] = nb;
    if (s.phone.isEmpty && b['phone'] is String) s.phone = b['phone'] as String;
    try {
      final menu = await api.get('/discover/branches/$bid/menu', auth: false) as J;
      for (final m in (menu['services'] as List? ?? const []).cast<J>()) {
        final mid = m['id'] as String;
        onMenu.add(mid);
        final old = db.services.where((x) => x.id == mid).firstOrNull;
        if (old == null) {
          db.services.add(
            ServiceItem(
              id: mid,
              salonId: id,
              name: m['name'] as String? ?? '',
              category: m['category'] as String? ?? 'Other',
              description: m['description'] as String? ?? '',
              price: money(m['price']),
              durationMin: asInt(m['durationMin'], 30),
            ),
          );
        } else {
          old
            ..name = m['name'] as String? ?? old.name
            ..description = m['description'] as String? ?? old.description
            ..category = m['category'] as String? ?? old.category
            ..price = money(m['price'])
            ..durationMin = asInt(m['durationMin'], old.durationMin);
        }
      }
      // Stylists customers can pick; their hours live on the server.
      for (final p in (menu['staff'] as List? ?? const []).cast<J>()) {
        final pid = p['id'] as String;
        mirrorPerson(db, pid, p['fullName'] as String? ?? '', salonId: id);
        final prof = db.staff.where((x) => x.accountId == pid).firstOrNull;
        if (prof == null) {
          db.staff.add(StaffProfile(accountId: pid, salonId: id, title: p['title'] as String? ?? '', week: [...hours], createdAt: now(), branchId: bid));
        } else {
          prof
            ..title = p['title'] as String? ?? prof.title
            ..branchId = bid; // takes bookings at this branch
        }
      }
    } catch (_) {
      // Menu unavailable right now: the salon still shows; try again next refresh.
      menusLoaded = false;
    }
  }
  // Branches HOLA doesn't have (deleted there, or made only on this phone by
  // an older version) go: saving them would fail. The rider's delivery stop stays.
  if (liveBranches.isNotEmpty) db.branches.removeWhere((b) => b.salonId == id && !liveBranches.contains(b.id) && !b.id.endsWith('~delivery'));
  // Drop services the server no longer offers (deleted there, or copies that
  // never reached it), so nobody can pick them and the booking fail. Hidden
  // services stay: the salon still sees and can switch them back on.
  if (menusLoaded) db.services.removeWhere((x) => x.salonId == id && x.active && !onMenu.contains(x.id));
  return s;
}

/// Upserts one appointment from the server (the shape POST /appointments and
/// GET /me/appointments return).
/// [actor]: who made the change, when it was made on this phone.
Appointment mirrorAppointment(LocalDatabase db, J j, {String? actor}) {
  final salon = j['salon'] as Map? ?? const {};
  final branch = j['branch'] as Map? ?? const {};
  final customer = j['customer'] as Map? ?? const {};
  final staff = j['staff'] as Map?;
  final salonId = salon['id'] as String? ?? '';
  final branchId = branch['id'] as String? ?? '';
  // A salon or branch the directory hasn't loaded (e.g. no longer live) still gets its name.
  if (!db.salons.any((s) => s.id == salonId)) {
    db.salons.add(Salon(id: salonId, ownerId: '', name: salon['name'] as String? ?? '', phone: '', status: SalonStatus.suspended, palette: salonId.hashCode.abs() % 6, hola: true, createdAt: now()));
  }
  if (!db.branches.any((b) => b.id == branchId)) {
    db.branches.add(Branch(id: branchId, salonId: salonId, name: branch['name'] as String? ?? '', address: branch['addressLine'] as String? ?? '', area: '', city: branch['city'] as String? ?? ''));
  }
  final staffId = staff?['id'] as String? ?? '';
  if (staff != null) mirrorPerson(db, staffId, staff['fullName'] as String? ?? '', salonId: salonId);
  final items = (j['items'] as List? ?? const []).cast<Map>();
  final start = DateTime.parse(j['startsAt'] as String).toLocal();
  final end = DateTime.parse(j['endsAt'] as String).toLocal();
  final a = Appointment(
    id: j['id'] as String,
    code: j['code'] as String? ?? '',
    salonId: salonId,
    branchId: branchId,
    customerId: customer['id'] as String?,
    customerName: customer['fullName'] as String? ?? '',
    customerPhone: customer['phone'] as String? ?? '',
    staffId: staffId,
    serviceIds: [for (final i in items) '${i['branchServiceId'] ?? i['id'] ?? ''}'],
    serviceNames: [for (final i in items) '${i['name'] ?? ''}'],
    startsAt: start,
    durationMin: end.difference(start).inMinutes,
    price: money(j['totalPrice']),
    status: j['status'] as String? ?? ApptStatus.requested,
    notes: j['notes'] as String? ?? '',
    lateCancel: j['lateCancel'] == true,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ?? now(),
    hola: true,
    version: asInt(j['version']),
    freeCancelUntil: DateTime.tryParse(j['freeCancelUntil'] as String? ?? '')?.toLocal(),
    // Contract 0.20.0: the server applies offers; each item says which.
    offerIds: [
      for (final i in items)
        if ((i['offer'] as Map?)?['id'] case final id?) '$id',
    ],
    discount: items.fold(0, (t, i) => t + money(i['discount'])),
  );
  final i = db.appointments.indexWhere((x) => x.id == a.id);
  final prev = i < 0 ? null : db.appointments[i];
  if (prev != null) {
    a.reviewed = prev.reviewed;
    a.history.addAll(prev.history);
  }
  // HOLA sends the current status only, so the timeline is built from what
  // this phone has seen: the request, then each status change it learns of.
  if (a.history.isEmpty) {
    // Made by the salon (source SALON): confirmed from the start.
    final bySalon = '${j['source'] ?? ''}'.toUpperCase() == 'SALON';
    a.history.add(StatusEvent(bySalon ? ApptStatus.confirmed : ApptStatus.requested, a.createdAt, bySalon ? (actor ?? '') : (a.customerId ?? ''), bySalon && a.customerId == null ? 'Walk-in' : null));
  }
  if (a.history.last.status != a.status && prev?.status != a.status) {
    final at = DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toLocal() ?? now();
    final by = actor ?? (a.status == ApptStatus.cancelledByCustomer ? (a.customerId ?? '') : '');
    final reason = (j['cancelReason'] as String?)?.trim();
    a.history.add(StatusEvent(a.status, at.isBefore(a.history.last.at) ? a.history.last.at : at, by, reason == null || reason.isEmpty ? null : reason));
  }
  i < 0 ? db.appointments.add(a) : db.appointments[i] = a;
  return a;
}

/// A branch's location from the server, in whichever shape it comes:
/// lat/lng on the branch, or a location/geo object.
GeoFix? branchGeo(Map b) {
  final g = b['location'] ?? b['geo'];
  final m = g is Map ? g : b;
  final lat = m['lat'] ?? m['latitude'], lng = m['lng'] ?? m['longitude'];
  if (lat == null || lng == null) return null;
  final la = double.tryParse('$lat'), ln = double.tryParse('$lng');
  return la == null || ln == null ? null : GeoFix(la, ln);
}

/// Upserts one offer from HOLA (a salon's list or GET /discover/offers).
ServiceOffer mirrorOffer(LocalDatabase db, J j) {
  final svc = j['service'] as Map? ?? const {};
  final salon = j['salon'] as Map?;
  final salonId = '${j['salonId'] ?? salon?['id'] ?? ''}';
  final o = ServiceOffer(
    id: j['id'] as String,
    salonId: salonId,
    serviceId: '${svc['id'] ?? j['serviceId'] ?? ''}',
    discountType: '${j['discountType'] ?? DiscountType.percent}'.toUpperCase(),
    discountValue: money(j['discountValue']),
    startsAt: DateTime.parse(j['startsAt'] as String).toLocal(),
    endsAt: DateTime.parse(j['endsAt'] as String).toLocal(),
    active: j['active'] != false,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ?? now(),
    hola: true,
    version: asInt(j['version']),
    serviceName: svc['name'] as String? ?? '',
    servicePrice: money(svc['price']),
    usedCount: asInt(j['usedCount']),
    reservedCount: asInt(j['reservedCount']),
    myUse: '${j['myUsage'] ?? OfferUse.none}'.toUpperCase(),
    heldOn: '${j['reservedOn'] ?? ''}',
  );
  final i = db.offers.indexWhere((x) => x.id == o.id);
  i < 0 ? db.offers.add(o) : db.offers[i] = o;
  return o;
}
