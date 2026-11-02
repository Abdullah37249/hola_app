import '../../core/l10n/l10n.dart';
import '../../core/utils/clock.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import 'local_auth_repository.dart';

class LocalEngagementRepository extends LocalRepository implements EngagementRepository {
  LocalEngagementRepository(super.db);

  Salon _salon(String id) => db.salons.where((s) => s.id == id).firstOrNull ?? (throw DomainError(tr('Salon not found.')));

  void _requireSalonSide(String salonId) {
    requireRole({Role.salonOwner, Role.salonStaff});
    if (requireMe.salonId != salonId) throw DomainError(tr('Not your salon.'));
  }

  // ── reviews ──

  @override
  List<Review> reviewsForSalon(String salonId) => db.reviews.where((r) => r.salonId == salonId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
    final r = Review(id: db.newId(), salonId: a.salonId, appointmentId: a.id, customerId: me.id, customerName: me.name, stars: stars, text: text.trim(), createdAt: now());
    db.reviews.add(r);
    a.reviewed = true;
    db.notifySalon(a.salonId, 'New {n}-star review', text.trim().isEmpty ? '{name} rated their visit.' : '{name}: “{text}”', args: {'n': '$stars', 'name': me.name, 'text': text.trim()}, icon: 'star', link: NotifLink('review', r.id));
    db.commit();
    return r;
  }

  @override
  Future<void> replyToReview(String reviewId, String reply) async {
    final r = db.reviews.where((x) => x.id == reviewId).firstOrNull ?? (throw DomainError(tr('Review not found.')));
    _requireSalonSide(r.salonId);
    if (reply.trim().length < 2) throw DomainError(tr('Write a reply.'));
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
    c
      ..status = 'RESOLVED'
      ..response = response.trim()
      ..resolvedAt = now();
    db.notify(c.customerId, '{salon} responded', '{text}', args: {'salon': _salon(c.salonId).name, 'text': response.trim()}, icon: 'msg', link: NotifLink('complaint', c.id));
    db.commit();
  }

  // ── chat ──

  @override
  List<ChatThread> threadsForCustomer(String customerId) => db.threads.where((t) => t.customerId == customerId && db.messages.any((m) => m.threadId == t.id)).toList()..sort((a, b) => b.lastAt.compareTo(a.lastAt));

  @override
  List<ChatThread> threadsForSalon(String salonId) => db.threads.where((t) => t.salonId == salonId && db.messages.any((m) => m.threadId == t.id)).toList()..sort((a, b) => b.lastAt.compareTo(a.lastAt));

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
    final mine = [for (var i = all.length - 1; i >= 0; i--) if (all[i].userId == id) (i, all[i])];
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
}
