import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../domain/entities/entities.dart';
import 'storage.dart';

/// The on-device database: every record of every role, persisted as one JSON
/// document. Repositories read and mutate it, then call [commit], which
/// notifies listeners (so all open screens refresh) and schedules a save.
class LocalDatabase extends ChangeNotifier {
  LocalDatabase(this._storage);
  final Storage _storage;
  static const _version = 1;

  final accounts = <Account>[];
  final staff = <StaffProfile>[];
  final leave = <LeaveRequest>[];
  final salons = <Salon>[];
  final branches = <Branch>[];
  final services = <ServiceItem>[];
  final appointments = <Appointment>[];
  final reviews = <Review>[];
  final complaints = <Complaint>[];
  final threads = <ChatThread>[];
  final messages = <ChatMessage>[];
  final notifications = <AppNotification>[];
  final products = <Product>[];
  final orders = <TradeOrder>[];
  final credit = <CreditEntry>[];
  final handovers = <CashHandover>[];
  final visits = <Visit>[];
  final trainings = <Training>[];
  final reports = <DailyReport>[];
  String? sessionAccountId;

  /// Device preferences (theme, sounds), not tied to an account.
  final prefs = <String, Object?>{};
  int _apptSeq = 10000, _orderSeq = 1000;

  bool _loaded = false;
  Timer? _saveTimer;
  Future<void>? _saving;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.read();
    if (raw != null && raw.isNotEmpty) _fromJson(decodeJson(raw) as Json);
    _loaded = true;
  }

  /// Call after every mutation.
  void commit() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), flush);
  }

  /// Writes pending changes now (also used before sign-out and in tests).
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _saving;
    _saving = _storage.write(encodeJson(_toJson()));
    await _saving;
  }

  // ── ids, codes, notifications ──

  final _rand = Random.secure();
  String newId() => List.generate(16, (_) => _rand.nextInt(16).toRadixString(16)).join();
  String newSalt() => List.generate(32, (_) => _rand.nextInt(16).toRadixString(16)).join();
  String nextAppointmentCode() => 'HB-${++_apptSeq}';
  String nextOrderCode() => 'SO-${++_orderSeq}';

  /// [title] and [body] are English templates; variable parts go in [args]
  /// (translated when shown, in the reader's language).
  void notify(String userId, String title, String body, {Map<String, String> args = const {}, String icon = 'bell', NotifLink? link}) {
    notifications.add(AppNotification(id: newId(), userId: userId, title: title, body: body, args: args, icon: icon, at: now(), link: link));
  }

  /// Notifies the owner and every staff member of a salon.
  void notifySalon(String salonId, String title, String body, {Map<String, String> args = const {}, String icon = 'bell', NotifLink? link, String? onlyStaffId}) {
    final s = salons.where((x) => x.id == salonId).firstOrNull;
    if (s == null) return;
    final ids = {s.ownerId, if (onlyStaffId != null) onlyStaffId};
    for (final id in ids) {
      notify(id, title, body, args: args, icon: icon, link: link);
    }
  }

  void notifyRole(Role role, String title, String body, {Map<String, String> args = const {}, String icon = 'bell', NotifLink? link}) {
    for (final a in accounts.where((a) => a.role == role)) {
      notify(a.id, title, body, args: args, icon: icon, link: link);
    }
  }

  // ── serialisation ──

  Json _toJson() => {
    'version': _version,
    'session': sessionAccountId,
    'prefs': prefs,
    'apptSeq': _apptSeq,
    'orderSeq': _orderSeq,
    'accounts': [for (final x in accounts) x.toJson()],
    'staff': [for (final x in staff) x.toJson()],
    'leave': [for (final x in leave) x.toJson()],
    'salons': [for (final x in salons) x.toJson()],
    'branches': [for (final x in branches) x.toJson()],
    'services': [for (final x in services) x.toJson()],
    'appointments': [for (final x in appointments) x.toJson()],
    'reviews': [for (final x in reviews) x.toJson()],
    'complaints': [for (final x in complaints) x.toJson()],
    'threads': [for (final x in threads) x.toJson()],
    'messages': [for (final x in messages) x.toJson()],
    'notifications': [for (final x in notifications) x.toJson()],
    'products': [for (final x in products) x.toJson()],
    'orders': [for (final x in orders) x.toJson()],
    'credit': [for (final x in credit) x.toJson()],
    'handovers': [for (final x in handovers) x.toJson()],
    'visits': [for (final x in visits) x.toJson()],
    'trainings': [for (final x in trainings) x.toJson()],
    'reports': [for (final x in reports) x.toJson()],
  };

  void _fromJson(Json j) {
    List<T> l<T>(String k, T Function(Json) f) => [for (final x in (j[k] as List? ?? const [])) f(x as Json)];
    sessionAccountId = j['session'];
    prefs.addAll((j['prefs'] as Map?)?.cast<String, Object?>() ?? const {});
    _apptSeq = (j['apptSeq'] as num?)?.toInt() ?? _apptSeq;
    _orderSeq = (j['orderSeq'] as num?)?.toInt() ?? _orderSeq;
    accounts.addAll(l('accounts', Account.fromJson));
    staff.addAll(l('staff', StaffProfile.fromJson));
    leave.addAll(l('leave', LeaveRequest.fromJson));
    salons.addAll(l('salons', Salon.fromJson));
    branches.addAll(l('branches', Branch.fromJson));
    services.addAll(l('services', ServiceItem.fromJson));
    appointments.addAll(l('appointments', Appointment.fromJson));
    reviews.addAll(l('reviews', Review.fromJson));
    complaints.addAll(l('complaints', Complaint.fromJson));
    threads.addAll(l('threads', ChatThread.fromJson));
    messages.addAll(l('messages', ChatMessage.fromJson));
    notifications.addAll(l('notifications', AppNotification.fromJson));
    products.addAll(l('products', Product.fromJson));
    orders.addAll(l('orders', TradeOrder.fromJson));
    credit.addAll(l('credit', CreditEntry.fromJson));
    handovers.addAll(l('handovers', CashHandover.fromJson));
    visits.addAll(l('visits', Visit.fromJson));
    trainings.addAll(l('trainings', Training.fromJson));
    reports.addAll(l('reports', DailyReport.fromJson));
  }
}
