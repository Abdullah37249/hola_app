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
      // Complaints: the customer's own, or those about the salon.
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
          resolvedAt: DateTime.tryParse(d['resolvedAt'] as String? ?? '')?.toLocal(),
        );
        final i = db.complaints.indexWhere((x) => x.id == c.id);
        i < 0 ? db.complaints.add(c) : db.complaints[i] = c;
      }
      // Reviews: a HOLA salon's own (to reply), or the customer's own.
      final res = m.role == Role.salonOwner && m.salonId != null && _hola(m.salonId!)
          ? await api!.get('/reviews', query: {'salonId': m.salonId!, 'pageSize': '100'})
          : m.role == Role.customer
          ? await api!.get('/me/reviews')
          : null;
      if (res != null) {
        for (final j in (res is Map ? res['data'] as List : res as List).cast<J>()) {
          final appt = j['appointment'] as Map? ?? const {};
          final r = Review(
            id: j['id'] as String,
            salonId: (j['salon'] as Map?)?['id'] as String? ?? '',
            appointmentId: appt['id'] as String? ?? '',
            customerId: (j['customer'] as Map?)?['id'] as String? ?? '',
            customerName: (j['customer'] as Map?)?['fullName'] as String? ?? '',
            stars: asInt(j['rating']),
            text: j['comment'] as String? ?? '',
            createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ?? now(),
            reply: j['salonReply'] as String?,
            repliedAt: DateTime.tryParse(j['repliedAt'] as String? ?? '')?.toLocal(),
            pending: j['status'] != 'PUBLISHED',
            version: asInt(j['version']),
          );
          final i = db.reviews.indexWhere((x) => x.id == r.id);
          i < 0 ? db.reviews.add(r) : db.reviews[i] = r;
          db.appointments.where((a) => a.id == r.appointmentId).firstOrNull?.reviewed = true;
        }
      }
      db.commit();
    } catch (_) {
      // Offline: keep what we have.
    }
  }

  Salon _salon(String id) => db.salons.where((s) => s.id == id).firstOrNull ?? (throw DomainError(tr('Salon not found.')));

  void _requireSalonSide(String salonId) {
    requireRole({Role.salonOwner, Role.salonStaff});
    if (requireMe.salonId != salonId) throw DomainError(tr('Not your salon.'));
  }

  // ── reviews ──

  @override
  List<Review> reviewsForSalon(String salonId) => db.reviews.where((r) => r.salonId == salonId && !r.pending).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Review? reviewForAppointment(String appointmentId) => db.reviews.where((r) => r.appointmentId == appointmentId).firstOrNull;

  @override
  Future<Review> addReview({required String appointmentId, required int stars, required String text}) async {
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
        res = await api!.post('/reviews', {'appointmentId': a.id, 'rating': stars, if (text.trim().isNotEmpty) 'comment': text.trim()}) as J;
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
      );
      db.reviews.add(r);
      a.reviewed = true;
      db.commit();
      return r;
    }
    final r = Review(id: db.newId(), salonId: a.salonId, appointmentId: a.id, customerId: me.id, customerName: me.name, stars: stars, text: text.trim(), createdAt: now());
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
      c.response = response.trim();
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

  // ── chat ──

  @override
  List<ChatThread> threadsForCustomer(String customerId) =>
      db.threads.where((t) => t.customerId == customerId && db.messages.any((m) => m.threadId == t.id)).toList()..sort((a, b) => b.lastAt.compareTo(a.lastAt));

  @override
  List<ChatThread> threadsForSalon(String salonId) =>
      db.threads.where((t) => t.salonId == salonId && db.messages.any((m) => m.threadId == t.id)).toList()..sort((a, b) => b.lastAt.compareTo(a.lastAt));

  @override
  ChatThread? thread(String id) => db.threads.where((t) => t.id == id).firstOrNull;

  @override
  Future<ChatThread> openThread(String salonId) async {
    requireRole({Role.customer});
    final me = requireMe;
    _salon(salonId);
    final existing = db.threads.where((t) => t.salonId == salonId && t.customerId == me.id).firstOrNull;
    if (existing != null) return existing;
    final t = ChatThread(id: db.newId(), salonId: salonId, customerId: me.id, lastAt: now());
    db.threads.add(t);
    db.commit();
    return t;
  }

  @override
  List<ChatMessage> messages(String threadId) => db.messages.where((m) => m.threadId == threadId).toList()..sort((a, b) => a.at.compareTo(b.at));

  @override
  ChatMessage? lastMessage(String threadId) {
    final ms = messages(threadId);
    return ms.isEmpty ? null : ms.last;
  }

  @override
  int unread(String threadId, {required bool asSalon}) => db.messages.where((m) => m.threadId == threadId && m.fromSalon != asSalon && !m.read).length;

  @override
  Future<void> send(String threadId, String text, {required bool asSalon}) async {
    final t = thread(threadId) ?? (throw DomainError(tr('Conversation not found.')));
    final me = requireMe;
    if (asSalon) {
      _requireSalonSide(t.salonId);
    } else if (t.customerId != me.id) {
      throw DomainError(tr('Not your conversation.'));
    }
    if (text.trim().isEmpty) return;
    if (text.trim().length > 1000) throw DomainError(tr('Messages can be up to 1000 characters.'));
    db.messages.add(ChatMessage(id: db.newId(), threadId: t.id, senderId: me.id, fromSalon: asSalon, text: text.trim(), at: now()));
    t.lastAt = now();
    final s = _salon(t.salonId);
    if (asSalon) {
      db.notify(t.customerId, '{salon}', '{text}', args: {'salon': s.name, 'text': text.trim()}, icon: 'msg', link: NotifLink('chat', t.id));
    } else {
      db.notifySalon(t.salonId, 'Message from {name}', '{text}', args: {'name': me.name, 'text': text.trim()}, icon: 'msg', link: NotifLink('chat', t.id));
    }
    db.commit();
  }

  @override
  Future<void> markThreadRead(String threadId, {required bool asSalon}) async {
    var changed = false;
    for (final m in db.messages.where((m) => m.threadId == threadId && m.fromSalon != asSalon && !m.read)) {
      m.read = true;
      changed = true;
    }
    if (changed) db.commit();
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
  }

  @override
  Future<void> markAllNotificationsRead() async {
    final id = requireMe.id;
    for (final n in db.notifications.where((n) => n.userId == id)) {
      n.read = true;
    }
    db.commit();
  }

  @override
  void receivePush(String title, String body, {NotifLink? link}) {
    final id = me?.id;
    if (id == null || (title.isEmpty && body.isEmpty)) return;
    db.notify(id, title, body, link: link);
    db.commit();
  }
}
