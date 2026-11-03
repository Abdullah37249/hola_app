import 'package:flutter/foundation.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/clock.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';

/// Read helpers shared by the customer viewmodels (salon names, people, hours).
mixin CustomerLookups {
  SalonRepository get salons;
  AuthRepository get auth;

  Account? get me => auth.current;
  Salon? salon(String id) => salons.salon(id);
  String salonName(String id) => salons.salon(id)?.name ?? tr('Salon');
  Branch? branch(String id) => salons.branch(id);
  String personName(String id) => auth.account(id)?.name ?? tr('A professional');

  /// "Gulberg III, Lahore" for the salon's first branch.
  String placeOf(String salonId) {
    final b = salons.branches(salonId).firstOrNull;
    return b == null ? '' : [b.area, b.city].where((x) => x.isNotEmpty).join(', ');
  }

  /// Bookable professionals with their account names.
  List<(StaffProfile, String)> team(String salonId) => [
    for (final p in salons.staff(salonId))
      if (p.bookable) (p, personName(p.accountId)),
  ];
}

/// Open/closed wording for a branch right now.
({bool open, String label}) openState(Branch b) {
  final t = now();
  final h = b.hoursOn(t);
  final m = t.hour * 60 + t.minute;
  if (h != null && m >= h.start && m < h.end) return (open: true, label: tr('Open until {time}', {'time': _hm(h.end)}));
  if (h != null && m < h.start) return (open: false, label: tr('Opens today at {time}', {'time': _hm(h.start)}));
  for (var i = 1; i <= 7; i++) {
    final d = addDays(t, i);
    final n = b.hoursOn(d);
    if (n != null) {
      return (open: false, label: i == 1 ? tr('Closed · opens tomorrow {time}', {'time': _hm(n.start)}) : tr('Closed · opens {day} {time}', {'day': tr(_wd[d.weekday - 1]), 'time': _hm(n.start)}));
    }
  }
  return (open: false, label: tr('Closed'));
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _hm(int m) {
  var h = m ~/ 60;
  final mm = m % 60;
  final ap = tr(h >= 12 && h < 24 ? 'pm' : 'am');
  h = (h + 11) % 12 + 1;
  return mm == 0 ? '$h $ap' : '$h:${mm.toString().padLeft(2, '0')} $ap';
}

String shiftLabel(Shift? s) => s == null ? tr('Closed') : '${_hm(s.start)} – ${_hm(s.end)}';

/// Home → Explore hand-off: a category to apply and/or a request to focus search.
class ExploreIntent extends ChangeNotifier {
  String? category;
  bool focusSearch = false;

  void browse(String? cat) {
    category = cat;
    notifyListeners();
  }

  void search() {
    focusSearch = true;
    notifyListeners();
  }
}

final exploreIntent = ExploreIntent();
