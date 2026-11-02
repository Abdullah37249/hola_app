/// App clock: one place to read the time, so tests can pin it.
DateTime Function() clock = DateTime.now;

DateTime now() => clock();
DateTime get today => dateOnly(now());
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
