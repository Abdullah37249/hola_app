import 'account.dart';
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
  // Trade credit (set by HOLA)
  int creditLimit, creditDays;
  final DateTime createdAt;

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
    this.creditLimit = 0,
    this.creditDays = 30,
    required this.createdAt,
  }) : photos = photos ?? [];

  String? get cover => photos.isEmpty ? null : photos.first;

  /// Verified by HOLA: shows the badge and unlocks trade ordering.
  bool get isActive => status == SalonStatus.active;
  /// Customers can find and book it (everything except a suspended salon).
  bool get isListed => status != SalonStatus.suspended;

  Json toJson() => {
        'id': id, 'ownerId': ownerId, 'name': name, 'phone': phone, 'about': about, 'status': status, 'statusNote': statusNote, 'palette': palette, 'photos': photos,
        'autoConfirm': autoConfirm, 'cancelWindowHours': cancelWindowHours, 'noShowGraceMin': noShowGraceMin, 'creditLimit': creditLimit, 'creditDays': creditDays,
        'createdAt': iso(createdAt),
      };

  factory Salon.fromJson(Json j) => Salon(
        id: j['id'], ownerId: j['ownerId'], name: j['name'], phone: j['phone'] ?? '', about: j['about'] ?? '', status: j['status'], statusNote: j['statusNote'],
        palette: asInt(j['palette']), photos: [for (final p in (j['photos'] as List? ?? const [])) p as String], autoConfirm: j['autoConfirm'] ?? false, cancelWindowHours: asInt(j['cancelWindowHours'], 2), noShowGraceMin: asInt(j['noShowGraceMin'], 15),
        creditLimit: asInt(j['creditLimit']), creditDays: asInt(j['creditDays'], 30), createdAt: dt(j['createdAt'])!,
      );
}

class Branch {
  final String id, salonId;
  String name, address, area, city;
  /// Opening hours indexed by weekday 1 (Mon) .. 7 (Sun); null = closed.
  final List<Shift?> hours;

  Branch({required this.id, required this.salonId, required this.name, required this.address, required this.area, required this.city, List<Shift?>? hours})
      : hours = hours ?? [for (var i = 0; i < 7; i++) i == 6 ? null : const Shift(10 * 60, 20 * 60)];

  Shift? hoursOn(DateTime d) => hours[d.weekday - 1];

  Json toJson() => {'id': id, 'salonId': salonId, 'name': name, 'address': address, 'area': area, 'city': city, 'hours': [for (final h in hours) h?.toJson()]};
  factory Branch.fromJson(Json j) => Branch(
        id: j['id'], salonId: j['salonId'], name: j['name'], address: j['address'] ?? '', area: j['area'] ?? '', city: j['city'] ?? '',
        hours: [for (final h in (j['hours'] as List)) h == null ? null : Shift.fromJson(h as Json)],
      );
}

class ServiceItem {
  final String id, salonId;
  String name, category, description;
  int price, durationMin;
  bool active;

  ServiceItem({required this.id, required this.salonId, required this.name, required this.category, this.description = '', required this.price, required this.durationMin, this.active = true});

  Json toJson() => {'id': id, 'salonId': salonId, 'name': name, 'category': category, 'description': description, 'price': price, 'durationMin': durationMin, 'active': active};
  factory ServiceItem.fromJson(Json j) => ServiceItem(
        id: j['id'], salonId: j['salonId'], name: j['name'], category: j['category'], description: j['description'] ?? '', price: asInt(j['price']),
        durationMin: asInt(j['durationMin']), active: j['active'] ?? true,
      );
}
