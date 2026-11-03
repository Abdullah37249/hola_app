import 'json.dart';

class Review {
  final String id, salonId, appointmentId, customerId, customerName;
  final int stars;
  final String text;
  final DateTime createdAt;
  String? reply;
  DateTime? repliedAt;

  /// Sent to HOLA, which checks reviews before they're public.
  bool pending;

  /// Server version (HOLA reviews), needed to reply.
  int version;

  Review({
    required this.id,
    required this.salonId,
    required this.appointmentId,
    required this.customerId,
    required this.customerName,
    required this.stars,
    required this.text,
    required this.createdAt,
    this.reply,
    this.repliedAt,
    this.pending = false,
    this.version = 0,
  });

  Json toJson() => {
    'id': id,
    'salonId': salonId,
    'appointmentId': appointmentId,
    'customerId': customerId,
    'customerName': customerName,
    'stars': stars,
    'text': text,
    'createdAt': iso(createdAt),
    'reply': reply,
    'repliedAt': iso(repliedAt),
    'pending': pending,
    'version': version,
  };
  factory Review.fromJson(Json j) => Review(
    id: j['id'],
    salonId: j['salonId'],
    appointmentId: j['appointmentId'],
    customerId: j['customerId'],
    customerName: j['customerName'],
    stars: asInt(j['stars']),
    text: j['text'] ?? '',
    createdAt: dt(j['createdAt'])!,
    reply: j['reply'],
    repliedAt: dt(j['repliedAt']),
    pending: j['pending'] ?? false,
    version: asInt(j['version']),
  );
}

/// Feedback or a complaint a customer raises with a salon.
class Complaint {
  final String id, salonId, customerId, customerName;
  final String? appointmentId;
  final String topic, text;
  String status; // OPEN | RESOLVED
  String? response;
  final DateTime createdAt;
  DateTime? resolvedAt;

  Complaint({
    required this.id,
    required this.salonId,
    required this.customerId,
    required this.customerName,
    this.appointmentId,
    required this.topic,
    required this.text,
    this.status = 'OPEN',
    this.response,
    required this.createdAt,
    this.resolvedAt,
  });

  Json toJson() => {
    'id': id,
    'salonId': salonId,
    'customerId': customerId,
    'customerName': customerName,
    'appointmentId': appointmentId,
    'topic': topic,
    'text': text,
    'status': status,
    'response': response,
    'createdAt': iso(createdAt),
    'resolvedAt': iso(resolvedAt),
  };
  factory Complaint.fromJson(Json j) => Complaint(
    id: j['id'],
    salonId: j['salonId'],
    customerId: j['customerId'],
    customerName: j['customerName'],
    appointmentId: j['appointmentId'],
    topic: j['topic'],
    text: j['text'],
    status: j['status'],
    response: j['response'],
    createdAt: dt(j['createdAt'])!,
    resolvedAt: dt(j['resolvedAt']),
  );
}

/// One conversation between a customer and a salon.
class ChatThread {
  final String id, salonId, customerId;
  DateTime lastAt;
  ChatThread({required this.id, required this.salonId, required this.customerId, required this.lastAt});
  Json toJson() => {'id': id, 'salonId': salonId, 'customerId': customerId, 'lastAt': iso(lastAt)};
  factory ChatThread.fromJson(Json j) => ChatThread(id: j['id'], salonId: j['salonId'], customerId: j['customerId'], lastAt: dt(j['lastAt'])!);
}

class ChatMessage {
  final String id, threadId, senderId;
  final bool fromSalon;
  final String text;
  final DateTime at;
  bool read;
  ChatMessage({required this.id, required this.threadId, required this.senderId, required this.fromSalon, required this.text, required this.at, this.read = false});
  Json toJson() => {'id': id, 'threadId': threadId, 'senderId': senderId, 'fromSalon': fromSalon, 'text': text, 'at': iso(at), 'read': read};
  factory ChatMessage.fromJson(Json j) =>
      ChatMessage(id: j['id'], threadId: j['threadId'], senderId: j['senderId'], fromSalon: j['fromSalon'], text: j['text'], at: dt(j['at'])!, read: j['read'] ?? false);
}

/// Where tapping a notification should take the user.
class NotifLink {
  final String type; // appointment | order | salon | visit | training | review | complaint | chat | leave
  final String id;
  const NotifLink(this.type, this.id);
  Json toJson() => {'type': type, 'id': id};
  factory NotifLink.fromJson(Json j) => NotifLink(j['type'], j['id']);
}

class AppNotification {
  /// [title] and [body] are English templates with `{placeholders}`, filled
  /// from [args] when shown: `tr(n.title, n.args)`. Stored untranslated so each
  /// reader sees them in their own language. Older records have no args.
  final String id, userId, title, body, icon;
  final Map<String, String> args;
  final DateTime at;
  final NotifLink? link;
  bool read;
  AppNotification({required this.id, required this.userId, required this.title, required this.body, this.args = const {}, this.icon = 'bell', required this.at, this.link, this.read = false});
  Json toJson() => {'id': id, 'userId': userId, 'title': title, 'body': body, 'args': args, 'icon': icon, 'at': iso(at), 'link': link?.toJson(), 'read': read};
  factory AppNotification.fromJson(Json j) => AppNotification(
    id: j['id'],
    userId: j['userId'],
    title: j['title'],
    body: j['body'],
    args: {for (final e in ((j['args'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    icon: j['icon'] ?? 'bell',
    at: dt(j['at'])!,
    link: j['link'] == null ? null : NotifLink.fromJson(j['link'] as Json),
    read: j['read'] ?? false,
  );
}
