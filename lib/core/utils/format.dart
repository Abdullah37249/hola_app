// Pure formatting helpers (no data access), in the current app language.

import '../l10n/l10n.dart';

const _daysEn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _daysUr = ['اتوار', 'پیر', 'منگل', 'بدھ', 'جمعرات', 'جمعہ', 'ہفتہ'];
const _monthsUr = ['جنوری', 'فروری', 'مارچ', 'اپریل', 'مئی', 'جون', 'جولائی', 'اگست', 'ستمبر', 'اکتوبر', 'نومبر', 'دسمبر'];

/// Short weekday names, Sunday first.
List<String> get days => L10n.ur ? _daysUr : _daysEn;

/// Short month names, January first.
List<String> get months => L10n.ur ? _monthsUr : _monthsEn;

/// PKR amount, e.g. `Rs 24,360`.
String rs(num n) {
  final s = n.round().abs().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  // Non-breaking space: an amount never wraps away from its currency.
  return 'Rs\u00A0${n < 0 ? '-' : ''}$s';
}

String fmtDur(int m) => m < 60 ? tr('{n} min', {'n': m}) : '${tr('{n} h', {'n': m ~/ 60})}${m % 60 != 0 ? ' ${tr('{n} min', {'n': m % 60})}' : ''}';

/// Decimal hours (16.5) → "4:30 pm".
String fmtT(double t) {
  var h = t.floor();
  final m = ((t - h) * 60).round();
  final ap = h >= 12 ? tr('pm') : tr('am');
  h = (h + 11) % 12 + 1;
  return '$h:${m.toString().padLeft(2, '0')} $ap';
}

int weekday0(DateTime d) => d.weekday % 7; // 0 = Sun, matches the API's weekday
String dLabel(DateTime d) => '${days[weekday0(d)]}, ${d.day} ${months[d.month - 1]}';

String initials(String name) => name.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join();

/// Minutes from midnight (630) → "10:30 am".
String fmtMin(int m) => fmtT(m / 60);

/// Time of a DateTime → "4:30 pm".
String fmtTime(DateTime d) => fmtMin(d.hour * 60 + d.minute);

/// "Today", "Tomorrow", "Yesterday" or "Wed, 4 Nov".
String dayLabel(DateTime d, DateTime today) {
  final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
  return switch (diff) { 0 => tr('Today'), 1 => tr('Tomorrow'), -1 => tr('Yesterday'), _ => dLabel(d) };
}

/// "just now", "5 min ago", "3 h ago", "2 days ago", then the date.
String ago(DateTime at, DateTime now) {
  final s = now.difference(at);
  if (s.inMinutes < 1) return tr('just now');
  if (s.inHours < 1) return tr('{n} min ago', {'n': s.inMinutes});
  if (s.inDays < 1) return tr('{n} h ago', {'n': s.inHours});
  if (s.inDays < 7) return s.inDays == 1 ? tr('yesterday') : tr('{n} days ago', {'n': s.inDays});
  return '${at.day} ${months[at.month - 1]}';
}

/// "1 item" / "3 items". The chosen English word is translated, so both
/// forms (e.g. 'service' and 'services') need Urdu entries.
String plural(int n, String one, [String? many]) => '$n ${tr(n == 1 ? one : (many ?? '${one}s'))}';
