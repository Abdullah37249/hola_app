import '../../core/l10n/l10n.dart';
import 'json.dart';

abstract final class VisitStatus {
  static const planned = 'PLANNED', checkedIn = 'CHECKED_IN', completed = 'COMPLETED', cancelled = 'CANCELLED';
}

/// Visit outcomes a sales officer can record. Fixed vocabulary.
List<(String, String)> get visitOutcomes => [('INTERESTED', tr('Interested')), ('ORDER_TAKEN', tr('Order taken')), ('TRAINING_DONE', tr('Training done')), ('PAYMENT_COLLECTED', tr('Payment collected')), ('FOLLOW_UP', tr('Follow-up needed')), ('NOT_INTERESTED', tr('Not interested'))];

class Visit {
  final String id, officerId, salonId;
  DateTime plannedFor;
  String purpose, status;
  DateTime? checkInAt, completedAt;
  final List<String> outcomes;
  String notes;
  DateTime? followUpAt;
  final DateTime createdAt;

  Visit({
    required this.id,
    required this.officerId,
    required this.salonId,
    required this.plannedFor,
    required this.purpose,
    this.status = VisitStatus.planned,
    this.checkInAt,
    this.completedAt,
    List<String>? outcomes,
    this.notes = '',
    this.followUpAt,
    required this.createdAt,
  }) : outcomes = outcomes ?? [];

  Json toJson() => {
        'id': id, 'officerId': officerId, 'salonId': salonId, 'plannedFor': iso(plannedFor), 'purpose': purpose, 'status': status, 'checkInAt': iso(checkInAt),
        'completedAt': iso(completedAt), 'outcomes': outcomes, 'notes': notes, 'followUpAt': iso(followUpAt), 'createdAt': iso(createdAt),
      };
  factory Visit.fromJson(Json j) => Visit(
        id: j['id'], officerId: j['officerId'], salonId: j['salonId'], plannedFor: dt(j['plannedFor'])!, purpose: j['purpose'] ?? '', status: j['status'],
        checkInAt: dt(j['checkInAt']), completedAt: dt(j['completedAt']), outcomes: strs(j['outcomes']), notes: j['notes'] ?? '', followUpAt: dt(j['followUpAt']),
        createdAt: dt(j['createdAt'])!,
      );
}

/// A training session HOLA runs; salon owners and staff enrol.
class Training {
  final String id, trainerId;
  String title, description, location;
  DateTime at;
  int durationMin, seats;
  final List<String> enrolled; // account ids
  final List<String> attended;
  String status; // SCHEDULED | COMPLETED | CANCELLED
  final DateTime createdAt;

  Training({
    required this.id,
    required this.trainerId,
    required this.title,
    this.description = '',
    required this.location,
    required this.at,
    this.durationMin = 120,
    required this.seats,
    List<String>? enrolled,
    List<String>? attended,
    this.status = 'SCHEDULED',
    required this.createdAt,
  })  : enrolled = enrolled ?? [],
        attended = attended ?? [];

  int get seatsLeft => seats - enrolled.length;

  Json toJson() => {
        'id': id, 'trainerId': trainerId, 'title': title, 'description': description, 'location': location, 'at': iso(at), 'durationMin': durationMin,
        'seats': seats, 'enrolled': enrolled, 'attended': attended, 'status': status, 'createdAt': iso(createdAt),
      };
  factory Training.fromJson(Json j) => Training(
        id: j['id'], trainerId: j['trainerId'], title: j['title'], description: j['description'] ?? '', location: j['location'] ?? '', at: dt(j['at'])!,
        durationMin: asInt(j['durationMin'], 120), seats: asInt(j['seats']), enrolled: strs(j['enrolled']), attended: strs(j['attended']), status: j['status'],
        createdAt: dt(j['createdAt'])!,
      );
}

/// End-of-day report a sales officer submits (figures computed from real activity).
class DailyReport {
  final String id, officerId;
  final DateTime day;
  final int visitsDone, visitsPlanned, ordersCount, ordersValue;
  final String notes;
  final DateTime submittedAt;
  const DailyReport({required this.id, required this.officerId, required this.day, required this.visitsDone, required this.visitsPlanned, required this.ordersCount, required this.ordersValue, required this.notes, required this.submittedAt});
  Json toJson() => {
        'id': id, 'officerId': officerId, 'day': iso(day), 'visitsDone': visitsDone, 'visitsPlanned': visitsPlanned, 'ordersCount': ordersCount,
        'ordersValue': ordersValue, 'notes': notes, 'submittedAt': iso(submittedAt),
      };
  factory DailyReport.fromJson(Json j) => DailyReport(
        id: j['id'], officerId: j['officerId'], day: dt(j['day'])!, visitsDone: asInt(j['visitsDone']), visitsPlanned: asInt(j['visitsPlanned']),
        ordersCount: asInt(j['ordersCount']), ordersValue: asInt(j['ordersValue']), notes: j['notes'] ?? '', submittedAt: dt(j['submittedAt'])!,
      );
}
