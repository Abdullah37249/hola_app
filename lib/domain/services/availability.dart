import '../entities/entities.dart';

/// A bookable start time and the professionals free for the whole duration.
class Slot {
  final DateTime start;
  final List<String> staffIds;
  const Slot(this.start, this.staffIds);
}

/// Computes bookable slots for one day. Pure: everything it needs is passed in.
///
/// A professional is free at `t` when the branch is open, they work that day
/// (shift, not on approved leave), and no chair-holding appointment of theirs
/// overlaps `[t, t + duration)`. Past times (plus [leadMin]) are excluded.
List<Slot> availableSlots({
  required DateTime day,
  required Branch branch,
  required List<StaffProfile> staff,
  required List<Appointment> appointments,
  required List<LeaveRequest> leave,
  required int durationMin,
  required DateTime now,
  int stepMin = 30,
  int leadMin = 30,
  String? onlyStaffId,
  String? ignoreAppointmentId,
}) {
  final open = branch.hoursOn(day);
  if (open == null || durationMin <= 0) return const [];
  final base = DateTime(day.year, day.month, day.day);
  final earliest = now.add(Duration(minutes: leadMin));
  final pros = staff.where((s) => s.bookable && (onlyStaffId == null || s.accountId == onlyStaffId)).toList();

  bool busy(String staffId, DateTime s, DateTime e) =>
      appointments.any((a) => a.id != ignoreAppointmentId && a.staffId == staffId && ApptStatus.holding.contains(a.status) && a.startsAt.isBefore(e) && a.endsAt.isAfter(s));
  bool onLeave(String staffId) => leave.any((l) => l.staffId == staffId && l.status == 'APPROVED' && l.covers(day));

  final out = <Slot>[];
  for (var m = open.start; m + durationMin <= open.end; m += stepMin) {
    final s = base.add(Duration(minutes: m)), e = s.add(Duration(minutes: durationMin));
    if (s.isBefore(earliest)) continue;
    final free = [
      for (final p in pros)
        if (p.shiftOn(day) case final sh? when sh.start <= m && m + durationMin <= sh.end && !onLeave(p.accountId) && !busy(p.accountId, s, e)) p.accountId,
    ];
    if (free.isNotEmpty) out.add(Slot(s, free));
  }
  return out;
}
