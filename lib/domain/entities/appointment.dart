import 'json.dart';

abstract final class ApptStatus {
  static const requested = 'REQUESTED', confirmed = 'CONFIRMED', declined = 'DECLINED', checkedIn = 'CHECKED_IN', inService = 'IN_SERVICE', completed = 'COMPLETED';
  static const cancelledByCustomer = 'CANCELLED_BY_CUSTOMER', cancelledBySalon = 'CANCELLED_BY_SALON', noShow = 'NO_SHOW';

  /// Statuses that still hold the chair (block the slot).
  static const holding = {requested, confirmed, checkedIn, inService};
  static const upcoming = {requested, confirmed};
  static const finished = {completed, declined, cancelledByCustomer, cancelledBySalon, noShow};
}

class StatusEvent {
  final String status, byId;
  final DateTime at;
  final String? note;
  const StatusEvent(this.status, this.at, this.byId, [this.note]);
  Json toJson() => {'status': status, 'at': iso(at), 'by': byId, 'note': note};
  factory StatusEvent.fromJson(Json j) => StatusEvent(j['status'], dt(j['at'])!, j['by'] ?? '', j['note']);
}

class Appointment {
  final String id, code, salonId, branchId;
  final String? customerId; // null for a walk-in guest
  final String customerName, customerPhone;
  String staffId;
  final List<String> serviceIds;
  final List<String> serviceNames; // snapshot at booking time
  DateTime startsAt;
  final int durationMin, price;
  String status;
  final String notes;
  bool lateCancel, reviewed;
  final List<StatusEvent> history;
  final DateTime createdAt;

  Appointment({
    required this.id,
    required this.code,
    required this.salonId,
    required this.branchId,
    this.customerId,
    required this.customerName,
    this.customerPhone = '',
    required this.staffId,
    required this.serviceIds,
    required this.serviceNames,
    required this.startsAt,
    required this.durationMin,
    required this.price,
    required this.status,
    this.notes = '',
    this.lateCancel = false,
    this.reviewed = false,
    List<StatusEvent>? history,
    required this.createdAt,
  }) : history = history ?? [];

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMin));
  bool get isWalkIn => customerId == null;
  StatusEvent? event(String s) => history.lastWhereOrNull((e) => e.status == s);

  Json toJson() => {
        'id': id, 'code': code, 'salonId': salonId, 'branchId': branchId, 'customerId': customerId, 'customerName': customerName, 'customerPhone': customerPhone,
        'staffId': staffId, 'serviceIds': serviceIds, 'serviceNames': serviceNames, 'startsAt': iso(startsAt), 'durationMin': durationMin, 'price': price,
        'status': status, 'notes': notes, 'lateCancel': lateCancel, 'reviewed': reviewed, 'history': [for (final h in history) h.toJson()], 'createdAt': iso(createdAt),
      };

  factory Appointment.fromJson(Json j) => Appointment(
        id: j['id'], code: j['code'], salonId: j['salonId'], branchId: j['branchId'], customerId: j['customerId'], customerName: j['customerName'],
        customerPhone: j['customerPhone'] ?? '', staffId: j['staffId'], serviceIds: strs(j['serviceIds']), serviceNames: strs(j['serviceNames']),
        startsAt: dt(j['startsAt'])!, durationMin: asInt(j['durationMin']), price: asInt(j['price']), status: j['status'], notes: j['notes'] ?? '',
        lateCancel: j['lateCancel'] ?? false, reviewed: j['reviewed'] ?? false, history: objs(j['history'], StatusEvent.fromJson), createdAt: dt(j['createdAt'])!,
      );
}

extension _LastWhere<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) f) {
    for (var i = length - 1; i >= 0; i--) {
      if (f(this[i])) return this[i];
    }
    return null;
  }
}
