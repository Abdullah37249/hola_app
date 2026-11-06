import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../core/utils/photo_files.dart';

import '../../core/push/push_service.dart' show pushLink;
import '../../core/l10n/l10n.dart';
import '../../core/utils/clock.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import 'local_auth_repository.dart';
import '../../core/network/api.dart';
import '../../domain/entities/json.dart' show asInt;

class LocalEngagementRepository extends LocalRepository implements EngagementRepository {
  LocalEngagementRepository(super.db, {this.api});

  /// When set, reviews and complaints about HOLA salons go to the HOLA server.
  final HolaApi? api;

  bool _hola(String salonId) => api != null && (db.salons.where((s) => s.id == salonId).firstOrNull?.hola ?? false);

  Future<T> _write<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on ApiError catch (e) {
      throw apiToDomain(e, fieldNames: const {'description': 'text', 'subject': 'topic'});
    }
  }

  /// The app's feedback topics as HOLA complaint categories.
  static String _category(String topic) => switch (topic) {
    'Staff behaviour' => 'STAFF',
    'Price or billing' => 'BILLING',
    'Booking problem' => 'APP',
    'Service quality' || 'Waiting time' || 'Hygiene' => 'SERVICE',
    _ => 'OTHER',
  };

  Future<void>? _syncing;

  @override
  Future<void> sync() => api == null ? Future.value() : (_syncing ??= _sync().whenComplete(() => _syncing = null));

  Future<void> _sync() async {
    final m = me;
    if (m == null) return;
    try {
      await _syncInbox(m.id);
    } catch (e) {
      debugPrint('Inbox: sync failed: $e'); // offline: keep what we have
    }
    // The reminder switch follows the account (set on another phone too).
    if (m.role == Role.customer) {
      try {
        final res = await api!.get('/me/notification-preferences');
        final items = (res is Map ? res['data'] ?? res['items'] : res) as List;
        final p = items.cast<Map>().where((x) => x['category'] == 'REMINDERS' && x['channel'] == 'PUSH').firstOrNull;
        if (p != null && (p['enabled'] == true) != remindersOn) {
          db.prefs[_remindersKey] = p['enabled'] == true;
          db.commit();
        }
      } catch (e) {
        debugPrint('Preferences: sync failed: $e');
      }
    }
    // Complaints: the customer's own, or those about the salon. On their own:
    // a failure here (HOLA dropped them in 0.30.0) mustn't stop the reviews.
    if (complaintsLive) {
      try {
        final list = await api!.get('/complaints', query: {'pageSize': '100'});
        for (final sum in (list is Map ? list['data'] as List : list as List).cast<J>()) {
          final salonId = (sum['salon'] as Map?)?['id'] as String?;
          if (salonId == null) continue;
          final d = await api!.get('/complaints/${sum['id']}') as J;
          final raisedBy = sum['raisedBy'] as Map? ?? const {};
          final msgs = (d['messages'] as List? ?? const []).cast<Map>().where((x) => x['internal'] != true && (x['author'] as Map?)?['id'] != raisedBy['id']).toList();
          final done = {'RESOLVED', 'CLOSED'}.contains(sum['status']);
          final c = Complaint(
            id: sum['id'] as String,
            salonId: salonId,
            customerId: raisedBy['id'] as String? ?? '',
            customerName: raisedBy['fullName'] as String? ?? '',
            appointmentId: d['appointmentId'] as String?,
            topic: sum['subject'] as String? ?? '',
            text: d['description'] as String? ?? '',
            status: done ? 'RESOLVED' : 'OPEN',
            response: d['resolution'] as String? ?? (msgs.isEmpty ? null : msgs.last['body'] as String?),
            createdAt: DateTime.tryParse(sum['createdAt'] as String? ?? '')?.toLocal() ?? now(),
            // When it was answered: resolved by HOLA, else the salon's last reply.
            resolvedAt: DateTime.tryParse(d['resolvedAt'] as String? ?? (msgs.isEmpty ? '' : '${msgs.last['createdAt'] ?? ''}'))?.toLocal(),
          );
          final i = db.complaints.indexWhere((x) => x.id == c.id);
          i < 0 ? db.complaints.add(c) : db.complaints[i] = c;
        }
      } catch (e) {
        debugPrint('Complaints: sync failed: $e');
      }
    }
    try {
      // Reviews: a HOLA salon's own (to reply), or the customer's own.
      final res = m.role == Role.salonOwner && m.salonId != null && _hola(m.salonId!)
          ? await api!.get('/reviews', query: {'salonId': m.salonId!, 'pageSize': '100'})
          : m.role == Role.customer
          ? await api!.get('/me/reviews')
          : null;
      if (res != null) {
        final seen = <String>{};
        for (final j in (res is Map ? res['data'] as List : res as List).cast<J>()) {
          // A review the salon deleted (0.24.0) leaves; the visit stays reviewed.
          final gone = j['status'] == 'DELETED' || j['deletedAt'] != null;
          final apptId = '${(j['appointment'] is Map ? (j['appointment'] as Map)['id'] : null) ?? j['appointmentId'] ?? ''}';
          db.appointments.where((a) => a.id == apptId).firstOrNull?.reviewed = true;
          // The salon's own list never has deleted ones; the customer keeps theirs, marked removed.
          if (gone && m.role != Role.customer) {
            db.reviews.removeWhere((x) => x.id == j['id']);
            continue;
          }
          final r = _keepReview(j);
          seen.add(r.id);
          db.appointments.where((a) => a.id == r.appointmentId).firstOrNull?.reviewed = true;
        }
        // The salon's own list: reviews it deleted elsewhere (another phone) leave too.
        if (m.role == Role.salonOwner && m.salonId != null) {
          db.reviews.removeWhere((x) => x.salonId == m.salonId && !seen.contains(x.id));
          // The whole list is here: the rating follows it at once, not only
          // when the salon's public profile is next fetched.
          final total = res is Map && res['meta'] is Map ? asInt((res['meta'] as Map)['total']) : seen.length;
          if (total <= seen.length) _rerate(m.salonId!);
        }
      }
      db.commit();
    } catch (_) {
      // Offline: keep what we have.
    }
  }

  /// A salon's rating from the reviews this phone holds (its own full list).
  void _rerate(String salonId) {
    final s = db.salons.where((x) => x.id == salonId).firstOrNull;
    if (s == null) return;
    final rs = db.reviews.where((r) => r.salonId == salonId && !r.pending && !r.removed).toList();
    s.ratingCount = rs.length;
    s.ratingAverage = rs.isEmpty ? null : rs.fold<int>(0, (a, r) => a + r.stars) / rs.length;
  }

  Salon _salon(String id) => db.salons.where((s) => s.id == id).firstOrNull ?? (throw DomainError(tr('Salon not found.')));

  void _requireSalonSide(String salonId) {
    requireRole({Role.salonOwner, Role.salonStaff});
    if (requireMe.salonId != salonId) throw DomainError(tr('Not your salon.'));
  }

  // ── booking reminders ──

  String get _remindersKey => 'reminders.${me?.id ?? ''}';

  @override
  bool get remindersOn => db.prefs[_remindersKey] as bool? ?? true;

  @override
  Future<void> setReminders(bool on) async {
    requireMe;
    if (api != null) {
      await _write(
        () => api!.put('/me/notification-preferences', {
          'items': [
            {'category': 'REMINDERS', 'channel': 'PUSH', 'enabled': on},
          ],
        }),
      );
    }
    db.prefs[_remindersKey] = on;
    db.commit();
  }

  // ── reviews ──

  /// Copies a HOLA review (ReviewView or PublicReviewView), keeping photos
  /// already downloaded to this phone.
  Review _keepReview(J j, {String? salonId}) {
    final appt = j['appointment'] as Map? ?? const {};
    final cust = j['customer'] as Map? ?? const {};
    final id = j['id'] as String;
    final old = db.reviews.where((x) => x.id == id).firstOrNull;
    final r = Review(
      id: id,
      salonId: (j['salon'] as Map?)?['id'] as String? ?? salonId ?? old?.salonId ?? '',
      appointmentId: appt['id'] as String? ?? j['appointmentId'] as String? ?? old?.appointmentId ?? '',
      customerId: cust['id'] as String? ?? old?.customerId ?? '',
      customerName: cust['fullName'] as String? ?? j['authorName'] as String? ?? j['customerName'] as String? ?? old?.customerName ?? '',
      stars: asInt(j['rating']),
      text: j['comment'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ?? now(),
      reply: j['salonReply'] as String? ?? (j['reply'] is Map ? (j['reply'] as Map)['body'] as String? : j['reply'] as String?),
      repliedAt: DateTime.tryParse(j['repliedAt'] as String? ?? '')?.toLocal(),
      // Public reviews are published by definition.
      pending: j.containsKey('status') && j['status'] != 'PUBLISHED' && j['status'] != 'DELETED',
      removed: j['status'] == 'DELETED' || j['deletedAt'] != null,
      version: asInt(j['version']),
      photos: [
        for (final p in (j['photos'] as List? ?? const []).cast<Map>())
          ReviewPhoto(fileId: '${p['fileId']}', kind: '${p['kind'] ?? 'OTHER'}', url: p['url'] as String?, local: old?.photos.where((x) => x.fileId == '${p['fileId']}').firstOrNull?.local),
      ],
    );
    final i = db.reviews.indexWhere((x) => x.id == r.id);
    i < 0 ? db.reviews.add(r) : db.reviews[i] = r;
    return r;
  }

  @override
  Future<void> syncSalonReviews(String salonId) async {
    if (api == null || !_hola(salonId)) return;
    try {
      final res = await api!.get('/discover/salons/$salonId/reviews', query: {'page': '1', 'pageSize': '50'}, auth: me != null) as J;
      final seen = <String>{};
      for (final j in (res['data'] as List).cast<J>()) {
        seen.add(_keepReview(j, salonId: salonId).id);
      }
      // Reviews HOLA took down leave the page (my own stay, with their status).
      db.reviews.removeWhere((r) => r.salonId == salonId && !r.pending && !seen.contains(r.id) && r.customerId != me?.id && me?.salonId != salonId);
      db.commit();
    } catch (e) {
      debugPrint('Reviews: sync failed: $e'); // offline: keep what we have
    }
  }

  /// The picked photo copied into the app's photo folder (or left where it is).
  Future<String> _keepPhoto(String path) async {
    try {
      return await PhotoFiles.keep(path);
    } catch (_) {
      return path;
    }
  }

  final _photoLoads = <String, Future<File?>>{};

  @override
  Future<File?> reviewPhotoFile(ReviewPhoto p) async {
    final local = p.local == null ? null : (PhotoFiles.file(p.local) ?? (File(p.local!).existsSync() ? File(p.local!) : null));
    if (local != null) return local;
    final id = p.fileId;
    if (id == null || api == null) return null;
    final name = 'review_$id';
    if (PhotoFiles.file(name) case final f?) {
      p.local = name;
      return f;
    }
    return _photoLoads[id] ??= () async {
      try {
        // A published photo has a public link; otherwise the author or the salon reads it with their sign-in.
        final bytes = p.url != null ? (await http.get(Uri.parse(p.url!))).bodyBytes : await api!.bytes('/files/$id/content');
        final f = await PhotoFiles.write(name, bytes);
        if (f != null) p.local = name;
        return f;
      } catch (_) {
        return null;
      } finally {
        _photoLoads.remove(id);
      }
    }();
  }

  @override
  List<Review> reviewsForSalon(String salonId, {bool withPending = false}) =>
      db.reviews.where((r) => r.salonId == salonId && !r.removed && (withPending || !r.pending)).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Review? reviewForAppointment(String appointmentId) => db.reviews.where((r) => r.appointmentId == appointmentId).firstOrNull;

  @override
  Future<Review> addReview({required String appointmentId, required int stars, required String text, List<(String, String)> photos = const []}) async {
    if (photos.length > 6) throw DomainError(tr('Add up to 6 photos.'));
    requireRole({Role.customer});
    final me = requireMe;
    final a = db.appointments.where((x) => x.id == appointmentId).firstOrNull ?? (throw DomainError(tr('Booking not found.')));
    if (a.customerId != me.id) throw DomainError(tr('Not your booking.'));
    if (a.status != ApptStatus.completed) throw DomainError(tr('You can review a visit once it is completed.'));
    if (reviewForAppointment(appointmentId) != null) throw DomainError(tr('You already reviewed this visit.'));
    if (stars < 1 || stars > 5) throw DomainError(tr('Choose 1 to 5 stars.'));
    if (a.hola && api != null) {
      final J res;
      try {
        // Photos go up first (as review_photo files), then the review names them.
        final sent = <Map<String, String>>[];
        for (final (path, kind) in photos) {
          final png = path.toLowerCase().endsWith('.png');
          final id = await api!.uploadFile(await File(path).readAsBytes(), contentType: png ? 'image/png' : 'image/jpeg', purpose: 'review_photo', fileName: 'review.${png ? 'png' : 'jpg'}');
          sent.add({'fileId': id, 'kind': kind});
        }
        res = await api!.post('/reviews', {'appointmentId': a.id, 'rating': stars, if (text.trim().isNotEmpty) 'comment': text.trim(), if (sent.isNotEmpty) 'photos': sent}) as J;
      } on ApiError catch (e) {
        if (e.status == 409) throw DomainError(tr('You already reviewed this visit.'));
        if (e.fields.containsKey('appointmentId')) throw DomainError(tr('This visit can’t be reviewed any more (reviews close 30 days after the visit).'));
        throw apiToDomain(e);
      }
      final r = Review(
        id: res['id'] as String,
        salonId: a.salonId,
        appointmentId: a.id,
        customerId: me.id,
        customerName: me.name,
        stars: stars,
        text: text.trim(),
        createdAt: now(),
        pending: res['status'] != 'PUBLISHED',
        version: asInt(res['version']),
        photos: [
          // The phone keeps its own copy, so the photos show straight away.
          for (final (i, p) in (res['photos'] as List? ?? const []).cast<Map>().indexed)
            ReviewPhoto(fileId: '${p['fileId']}', kind: '${p['kind'] ?? 'OTHER'}', url: p['url'] as String?, local: i < photos.length ? await _keepPhoto(photos[i].$1) : null),
        ],
      );
      db.reviews.add(r);
      a.reviewed = true;
      db.commit();
      return r;
    }
    final r = Review(
      id: db.newId(),
      salonId: a.salonId,
      appointmentId: a.id,
      customerId: me.id,
      customerName: me.name,
      stars: stars,
      text: text.trim(),
      createdAt: now(),
      photos: [for (final (path, kind) in photos) ReviewPhoto(kind: kind, local: await _keepPhoto(path))],
    );
    db.reviews.add(r);
    a.reviewed = true;
    db.notifySalon(
      a.salonId,
      'New {n}-star review',
      text.trim().isEmpty ? '{name} rated their visit.' : '{name}: “{text}”',
      args: {'n': '$stars', 'name': me.name, 'text': text.trim()},
      icon: 'star',
      link: NotifLink('review', r.id),
    );
    db.commit();
    return r;
  }

  @override
  Future<void> replyToReview(String reviewId, String reply) async {
    final r = db.reviews.where((x) => x.id == reviewId).firstOrNull ?? (throw DomainError(tr('Review not found.')));
    _requireSalonSide(r.salonId);
    if (reply.trim().length < 2) throw DomainError(tr('Write a reply.'));
    if (_hola(r.salonId)) {
      await _write(() => api!.post('/reviews/$reviewId/reply', {'reply': reply.trim(), 'version': r.version}));
      r
        ..reply = reply.trim()
        ..repliedAt = now()
        ..version += 1;
      db.commit();
      return;
    }
    r
      ..reply = reply.trim()
      ..repliedAt = now();
    db.notify(r.customerId, '{salon} replied to your review', '{text}', args: {'salon': _salon(r.salonId).name, 'text': reply.trim()}, icon: 'msg', link: NotifLink('review', r.id));
    db.commit();
  }

  /// DELETE /reviews/{id} is live on HOLA (contract 0.24.0).
  static bool reviewDeleteLive = true;

  /// /complaints* on HOLA: removed in contract 0.30.0 (404).
  static bool complaintsLive = false;

  @override
  bool get complaintsOn => api == null || complaintsLive;

  @override
  bool get reviewDelete => api == null || reviewDeleteLive;

  @override
  Future<void> deleteReview(String reviewId) async {
    final r = db.reviews.where((x) => x.id == reviewId).firstOrNull ?? (throw DomainError(tr('Review not found.')));
    _requireSalonSide(r.salonId);
    if (_hola(r.salonId)) {
      if (!reviewDeleteLive) throw DomainError(tr('Deleting reviews opens once HOLA switches it on.'));
      await _write(() => api!.delete('/reviews/$reviewId'));
    }
    // Off the profile and the rating; the customer still sees it, marked removed,
    // and can't post a second one for the same visit.
    r.removed = true;
    _rerate(r.salonId);
    db.commit();
  }

  // ── complaints ──

  @override
  List<Complaint> complaintsForSalon(String salonId) => db.complaints.where((c) => c.salonId == salonId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  List<Complaint> complaintsForCustomer(String customerId) => db.complaints.where((c) => c.customerId == customerId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<Complaint> raiseComplaint({required String salonId, String? appointmentId, required String topic, required String text}) async {
    requireRole({Role.customer});
    final me = requireMe;
    _salon(salonId);
    if (topic.trim().isEmpty) throw DomainError(tr('Pick what it is about.'));
    if (text.trim().length < 10) throw DomainError(tr('Tell us a little more (at least 10 characters).'));
    if (_hola(salonId)) {
      final res =
          await _write(() => api!.post('/complaints', {'category': _category(topic), 'subject': topic.trim(), 'description': text.trim(), 'salonId': salonId, 'appointmentId': ?appointmentId})) as J;
      final c = Complaint(id: res['id'] as String, salonId: salonId, customerId: me.id, customerName: me.name, appointmentId: appointmentId, topic: topic.trim(), text: text.trim(), createdAt: now());
      db.complaints.add(c);
      db.commit();
      return c;
    }
    final c = Complaint(id: db.newId(), salonId: salonId, customerId: me.id, customerName: me.name, appointmentId: appointmentId, topic: topic.trim(), text: text.trim(), createdAt: now());
    db.complaints.add(c);
    db.notifySalon(salonId, 'New feedback: {topic}', '{name}: {text}', args: {'topic': c.topic, 'name': me.name, 'text': c.text}, icon: 'alert', link: NotifLink('complaint', c.id));
    db.commit();
    return c;
  }

  @override
  Future<void> resolveComplaint(String id, String response) async {
    final c = db.complaints.where((x) => x.id == id).firstOrNull ?? (throw DomainError(tr('Not found.')));
    _requireSalonSide(c.salonId);
    if (response.trim().length < 5) throw DomainError(tr('Write a response to the customer.'));
    if (_hola(c.salonId)) {
      // The salon answers in the complaint's thread; HOLA closes it.
      await _write(() => api!.post('/complaints/$id/messages', {'body': response.trim()}));
      c
        ..response = response.trim()
        ..resolvedAt = now();
      db.commit();
      return;
    }
    c
      ..status = 'RESOLVED'
      ..response = response.trim()
      ..resolvedAt = now();
    db.notify(c.customerId, '{salon} responded', '{text}', args: {'salon': _salon(c.salonId).name, 'text': response.trim()}, icon: 'msg', link: NotifLink('complaint', c.id));
    db.commit();
  }

  // ── notifications ──

  @override
  List<AppNotification> notifications() {
    final id = me?.id;
    // Newest first; ties (same instant) keep the most recently added on top.
    final all = db.notifications;
    final mine = [
      for (var i = all.length - 1; i >= 0; i--)
        if (all[i].userId == id) (i, all[i]),
    ];
    mine.sort((a, b) => b.$2.at.compareTo(a.$2.at) != 0 ? b.$2.at.compareTo(a.$2.at) : b.$1.compareTo(a.$1));
    return [for (final x in mine) x.$2];
  }

  @override
  int unreadNotifications() {
    final id = me?.id;
    return db.notifications.where((n) => n.userId == id && !n.read).length;
  }

  @override
  Future<void> markNotificationRead(String id) async {
    final n = db.notifications.where((x) => x.id == id).firstOrNull;
    if (n == null || n.read) return;
    n.read = true;
    db.commit();
    // HOLA's inbox too, so other phones show it read.
    if (api != null && id.startsWith(_inbox)) {
      api!.post('/me/notifications/${id.substring(_inbox.length)}/read', const {}).catchError((Object e) => debugPrint('Inbox: read failed: $e'));
    }
  }

  @override
  Future<void> markAllNotificationsRead() async {
    final id = requireMe.id;
    for (final n in db.notifications.where((n) => n.userId == id)) {
      n.read = true;
    }
    db.commit();
    if (api != null) api!.post('/me/notifications/read-all', const {}).catchError((Object e) => debugPrint('Inbox: read-all failed: $e'));
  }

  /// Ids of notifications that come from HOLA's inbox.
  static const _inbox = 'hola:';

  /// HOLA's in-app inbox (newest 100), so a new phone or a reinstall shows
  /// the same list, and what's read on one phone is read on all.
  Future<void> _syncInbox(String userId) async {
    for (var page = 1; page <= 2; page++) {
      final res = await api!.get('/me/notifications', query: {'page': '$page', 'pageSize': '50'});
      final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<Map>();
      for (final j in list) {
        final id = '$_inbox${j['id']}';
        final read = j['readAt'] != null;
        final have = db.notifications.where((n) => n.id == id).firstOrNull;
        if (have != null) {
          if (read) have.read = true;
          continue;
        }
        final at = DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? now();
        final link = pushLink({for (final e in ((j['data'] as Map?) ?? const {}).entries) '${e.key}': e.value});
        final body = '${j['body'] ?? ''}';
        // This phone's own note of the same news (from the push before it
        // carried an id, or from a sync): HOLA's entry replaces it.
        db.notifications.removeWhere(
          (n) =>
              n.userId == userId &&
              !n.id.startsWith(_inbox) &&
              link != null &&
              n.link?.type == link.type &&
              n.link?.id == link.id &&
              n.at.difference(at).inMinutes.abs() < 3 &&
              (link.type != 'chat' || n.body == body),
        );
        db.notifications.add(
          AppNotification(
            id: id,
            userId: userId,
            title: '${j['title'] ?? ''}',
            body: body,
            icon: switch ('${j['category'] ?? ''}') {
              'BOOKINGS' => 'cal',
              'MESSAGES' || 'CHAT' => 'msg',
              'REVIEWS' => 'star',
              _ => 'bell',
            },
            at: at,
            link: link,
            read: read,
          ),
        );
      }
      final meta = res is Map ? res['meta'] as Map? : null;
      if (list.length < 50 || page >= asInt(meta?['totalPages'], 1)) break;
    }
  }

  @override
  void receivePush(String title, String body, {NotifLink? link, String? inboxId}) {
    final id = me?.id;
    if (id == null || (title.isEmpty && body.isEmpty)) return;
    if (inboxId != null && inboxId.isNotEmpty) {
      final key = '$_inbox$inboxId';
      if (db.notifications.any((n) => n.id == key)) return;
      if (link?.type != 'chat') {
        final old = db.recentAbout(id, link);
        if (old != null && !old.read) db.notifications.remove(old);
      }
      db.notifications.add(AppNotification(id: key, userId: id, title: title, body: body, at: now(), link: link));
      db.commit();
      return;
    }
    // The sync may have told of this change a moment ago: keep HOLA's wording.
    // (Chat messages each stay: several can arrive in a row.)
    if (link?.type != 'chat') {
      final old = db.recentAbout(id, link);
      if (old != null && !old.read) db.notifications.remove(old);
    }
    db.notify(id, title, body, link: link);
    db.commit();
  }
}
