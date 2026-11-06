import 'account.dart';
import 'geo.dart';
import 'json.dart';

/// Salon lifecycle (subset of the HOLA workflow that makes sense on-device).
abstract final class SalonStatus {
  static const pending = 'PENDING_VERIFICATION', changes = 'CHANGES_REQUESTED', active = 'ACTIVE', suspended = 'SUSPENDED';
}

/// Service categories customers browse by. Fixed vocabulary, not data.
const serviceCategories = ['Hair', 'Colour', 'Nails', 'Skin', 'Bridal', 'Barber', 'Spa', 'Makeup'];

class Salon {
  final String id, ownerId;
  String name, phone, about;
  String status;
  String? statusNote; // e.g. what the officer asked to change
  final int palette; // artwork colourway
  /// Photo file names on this device; the first is the cover.
  List<String> photos;
  // Booking policy
  bool autoConfirm;
  int cancelWindowHours, noShowGraceMin;

  /// How early a booking can be checked in (HOLA: booking-policy effective.checkInEarlyMin).
  int checkInEarlyMin;
  // Trade credit (set by HOLA)
  int creditLimit, creditDays;
  final DateTime createdAt;

  /// Comes from the HOLA server (read-only on the phone until salon editing
  /// and bookings are connected).
  final bool hola;

  /// The owner to call, as HOLA sends it with a delivery (rider app only).
  String? ownerName, ownerPhone;

  /// HOLA's rating from published reviews (contract 0.18.0); null until the
  /// directory has been synced. On-device salons work theirs out locally.
  double? ratingAverage;
  int? ratingCount;

  Salon({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.phone,
    this.about = '',
    this.status = SalonStatus.pending,
    this.statusNote,
    required this.palette,
    List<String>? photos,
    this.autoConfirm = false,
    this.cancelWindowHours = 2,
    this.noShowGraceMin = 15,
    this.checkInEarlyMin = 120,
    this.creditLimit = 0,
    this.creditDays = 30,
    this.hola = false,
    required this.createdAt,
  }) : photos = photos ?? [];

  String? get cover => photos.isEmpty ? null : photos.first;

  /// Verified by HOLA: shows the badge and unlocks trade ordering.
  bool get isActive => status == SalonStatus.active;

  /// Customers can find and book it (everything except a suspended salon).
  bool get isListed => status != SalonStatus.suspended;

  Json toJson() => {
    'id': id,
    'ownerId': ownerId,
    'name': name,
    'phone': phone,
    'about': about,
    'status': status,
    'statusNote': statusNote,
    'palette': palette,
    'photos': photos,
    'autoConfirm': autoConfirm,
    'cancelWindowHours': cancelWindowHours,
    'noShowGraceMin': noShowGraceMin,
    'checkInEarlyMin': checkInEarlyMin,
    'creditLimit': creditLimit,
    'creditDays': creditDays,
    'createdAt': iso(createdAt),
    'hola': hola,
    if (ownerName != null) 'ownerName': ownerName,
    if (ownerPhone != null) 'ownerPhone': ownerPhone,
    if (ratingCount != null) 'ratingCount': ratingCount,
    if (ratingAverage != null) 'ratingAverage': ratingAverage,
  };

  factory Salon.fromJson(Json j) =>
      Salon(
          id: j['id'],
          ownerId: j['ownerId'],
          name: j['name'],
          phone: j['phone'] ?? '',
          about: j['about'] ?? '',
          status: j['status'],
          statusNote: j['statusNote'],
          palette: asInt(j['palette']),
          photos: [for (final p in (j['photos'] as List? ?? const [])) p as String],
          autoConfirm: j['autoConfirm'] ?? false,
          cancelWindowHours: asInt(j['cancelWindowHours'], 2),
          noShowGraceMin: asInt(j['noShowGraceMin'], 15),
          checkInEarlyMin: asInt(j['checkInEarlyMin'], 120),
          creditLimit: asInt(j['creditLimit']),
          creditDays: asInt(j['creditDays'], 30),
          hola: j['hola'] ?? false,
          createdAt: dt(j['createdAt'])!,
        )
        ..ownerName = j['ownerName']
        ..ownerPhone = j['ownerPhone']
        ..ratingCount = j['ratingCount'] == null ? null : asInt(j['ratingCount'])
        ..ratingAverage = (j['ratingAverage'] as num?)?.toDouble();
}

class Branch {
  final String id, salonId;
  String name, address, area, city;

  /// Where the branch is (GPS captured at the door), for riders' navigation.
  GeoFix? location;

  /// HOLA's ready Google Maps directions link (GPS, or the address when none).
  String? mapsUrl;

  /// Opening hours indexed by weekday 1 (Mon) .. 7 (Sun); null = closed.
  final List<Shift?> hours;

  Branch({required this.id, required this.salonId, required this.name, required this.address, required this.area, required this.city, List<Shift?>? hours, this.location})
    : hours = hours ?? [for (var i = 0; i < 7; i++) i == 6 ? null : const Shift(10 * 60, 20 * 60)];

  Shift? hoursOn(DateTime d) => hours[d.weekday - 1];

  Json toJson() => {
    'id': id,
    'salonId': salonId,
    'name': name,
    'address': address,
    'area': area,
    'city': city,
    'hours': [for (final h in hours) h?.toJson()],
    if (location != null) 'location': location!.toJson(),
    if (mapsUrl != null) 'mapsUrl': mapsUrl,
  };
  factory Branch.fromJson(Json j) => Branch(
    id: j['id'],
    salonId: j['salonId'],
    name: j['name'],
    address: j['address'] ?? '',
    area: j['area'] ?? '',
    city: j['city'] ?? '',
    hours: [for (final h in (j['hours'] as List)) h == null ? null : Shift.fromJson(h as Json)],
    location: GeoFix.fromJson(j['location']),
  )..mapsUrl = j['mapsUrl'];
}

class ServiceItem {
  final String id, salonId;
  String name, category, description;
  int price, durationMin;
  bool active;

  ServiceItem({required this.id, required this.salonId, required this.name, required this.category, this.description = '', required this.price, required this.durationMin, this.active = true});

  Json toJson() => {'id': id, 'salonId': salonId, 'name': name, 'category': category, 'description': description, 'price': price, 'durationMin': durationMin, 'active': active};
  factory ServiceItem.fromJson(Json j) => ServiceItem(
    id: j['id'],
    salonId: j['salonId'],
    name: j['name'],
    category: j['category'],
    description: j['description'] ?? '',
    price: asInt(j['price']),
    durationMin: asInt(j['durationMin']),
    active: j['active'] ?? true,
  );
}

/// How an offer takes money off a service.
abstract final class DiscountType {
  static const percent = 'PERCENT', amount = 'FIXED'; // HOLA's names (contract 0.20.0)
}

/// Where a customer stands with one offer (it can be used once).
abstract final class OfferUse {
  /// Free to use on a new booking.
  static const none = 'NONE';

  /// On a booking that is still open; freed again if that booking is cancelled.
  static const reserved = 'RESERVED';

  /// Spent: the booking that used it was completed, or the client didn't come.
  static const used = 'USED';
}

/// A salon's promotion on one of its services, e.g. "Facial – 25% off until 6 Nov".
class ServiceOffer {
  final String id, salonId;
  String serviceId;
  String discountType;

  /// Percent (1–90) or rupees off, by [discountType].
  int discountValue;

  /// Live from [startsAt] until just before [endsAt] (the day after the last day).
  DateTime startsAt, endsAt;
  bool active;
  final DateTime createdAt;

  /// Kept on the HOLA server; [version] guards edits there.
  final bool hola;
  int version;

  /// The service as the server last described it (shown if the menu hasn't loaded).
  String serviceName;
  int servicePrice;

  /// Salon side: customers who used it / hold it on an open booking (HOLA only).
  int usedCount, reservedCount;

  /// Customer side, from HOLA: this customer's use ([OfferUse]) and the booking holding it.
  String myUse;
  String heldOn;

  ServiceOffer({
    required this.id,
    required this.salonId,
    required this.serviceId,
    required this.discountType,
    required this.discountValue,
    required this.startsAt,
    required this.endsAt,
    this.active = true,
    required this.createdAt,
    this.hola = false,
    this.version = 0,
    this.serviceName = '',
    this.servicePrice = 0,
    this.usedCount = 0,
    this.reservedCount = 0,
    this.myUse = OfferUse.none,
    this.heldOn = '',
  });

  bool get isPercent => discountType == DiscountType.percent;

  /// Rupees off [price] (never more than the price).
  int discountOn(int price) => (isPercent ? (price * discountValue / 100).round() : discountValue).clamp(0, price);

  /// Running and switched on at [t].
  bool liveAt(DateTime t) => active && !t.isBefore(startsAt) && t.isBefore(endsAt);

  /// ACTIVE, SCHEDULED, EXPIRED or INACTIVE at [t].
  String statusAt(DateTime t) => !t.isBefore(endsAt)
      ? 'EXPIRED'
      : !active
      ? 'INACTIVE'
      : t.isBefore(startsAt)
      ? 'SCHEDULED'
      : 'ACTIVE';

  /// The last day it runs.
  DateTime get lastDay => endsAt.subtract(const Duration(minutes: 1));

  Json toJson() => {
    'id': id,
    'salonId': salonId,
    'serviceId': serviceId,
    'discountType': discountType,
    'discountValue': discountValue,
    'startsAt': iso(startsAt),
    'endsAt': iso(endsAt),
    'active': active,
    'createdAt': iso(createdAt),
    'hola': hola,
    'version': version,
    'serviceName': serviceName,
    'servicePrice': servicePrice,
    'usedCount': usedCount,
    'reservedCount': reservedCount,
    'myUse': myUse,
    'heldOn': heldOn,
  };

  factory ServiceOffer.fromJson(Json j) => ServiceOffer(
    id: j['id'],
    salonId: j['salonId'],
    serviceId: j['serviceId'],
    discountType: j['discountType'] == 'AMOUNT' ? DiscountType.amount : j['discountType'] ?? DiscountType.percent,
    discountValue: asInt(j['discountValue']),
    startsAt: dt(j['startsAt'])!,
    endsAt: dt(j['endsAt'])!,
    active: j['active'] ?? true,
    createdAt: dt(j['createdAt'])!,
    hola: j['hola'] ?? false,
    version: asInt(j['version']),
    serviceName: j['serviceName'] ?? '',
    servicePrice: asInt(j['servicePrice']),
    usedCount: asInt(j['usedCount']),
    reservedCount: asInt(j['reservedCount']),
    myUse: j['myUse'] ?? OfferUse.none,
    heldOn: j['heldOn'] ?? '',
  );
}

/// The largest rupee discount an offer may give on a service: 90% of its price
/// (the same cap as a percent offer; HOLA enforces it too).
int maxOfferAmount(int price) => price * 9 ~/ 10;
