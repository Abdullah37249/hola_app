import 'json.dart';

/// A photo on a review: before, after, or other.
class ReviewPhoto {
  ReviewPhoto({this.fileId, this.kind = 'OTHER', this.url, this.local});

  /// HOLA's file (null for an on-device review).
  final String? fileId;

  /// BEFORE, AFTER or OTHER.
  final String kind;

  /// Public link, while the review is published.
  final String? url;

  /// The photo on this phone (picked here, or downloaded once).
  String? local;

  Json toJson() => {'fileId': fileId, 'kind': kind, 'url': url, 'local': local};
  factory ReviewPhoto.fromJson(Json j) => ReviewPhoto(fileId: j['fileId'], kind: j['kind'] ?? 'OTHER', url: j['url'], local: j['local']);
}

class Review {
  final String id, salonId, appointmentId, customerId, customerName;
  final int stars;
  final String text;
  final DateTime createdAt;
  String? reply;
  DateTime? repliedAt;

  /// Sent to HOLA, which checks reviews before they're public.
  bool pending;

  /// The salon deleted it (contract 0.24.0): gone from its profile and
  /// rating; the customer still sees it, marked as removed.
  bool removed;

  /// Server version (HOLA reviews), needed to reply.
  int version;

  /// Before/after photos (up to 6).
  List<ReviewPhoto> photos;

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
    this.removed = false,
    this.version = 0,
    List<ReviewPhoto>? photos,
  }) : photos = photos ?? [];

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
    if (removed) 'removed': true,
    'version': version,
    if (photos.isNotEmpty) 'photos': [for (final p in photos) p.toJson()],
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
    removed: j['removed'] ?? false,
    version: asInt(j['version']),
    photos: objs(j['photos'], ReviewPhoto.fromJson),
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

/// Who wrote a chat message.
abstract final class ChatSide {
  static const customer = 'CUSTOMER', salon = 'SALON', rider = 'RIDER', hola = 'HOLA';
}

/// A conversation is customer↔salon or rider↔salon.
abstract final class ChatKind {
  static const customerSalon = 'CUSTOMER_SALON', riderSalon = 'RIDER_SALON';

  /// HOLA's team and a salon: general, or about a return (contract 0.23.0).
  static const holaSalon = 'HOLA_SALON';
}

/// One conversation, optionally about a booking (APPOINTMENT) or an order
/// (ORDER). Names are copied in so the inbox can show them for anyone.
class ChatThread {
  final String id, kind, salonId;
  final String? customerId, riderId;
  String salonName, customerName, customerPhone, riderName, riderPhone;

  /// 'APPOINTMENT', 'ORDER' or 'RETURN' (null: a general conversation).
  final String? contextType, contextId;
  String contextCode;
  DateTime lastAt;

  /// Unread count from HOLA for the viewer's side (server conversations).
  int serverUnread;

  /// Lives on the HOLA server.
  final bool hola;

  /// There may be older messages on the server than this phone has.
  bool hasOlder;

  ChatThread({
    required this.id,
    this.kind = ChatKind.customerSalon,
    required this.salonId,
    this.customerId,
    this.riderId,
    this.salonName = '',
    this.customerName = '',
    this.customerPhone = '',
    this.riderName = '',
    this.riderPhone = '',
    this.contextType,
    this.contextId,
    this.contextCode = '',
    required this.lastAt,
    this.serverUnread = 0,
    this.hola = false,
    this.hasOlder = false,
  });

  bool get withRider => kind == ChatKind.riderSalon;
  bool get withHola => kind == ChatKind.holaSalon;

  Json toJson() => {
    'id': id,
    'kind': kind,
    'salonId': salonId,
    'customerId': customerId,
    'riderId': riderId,
    'salonName': salonName,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'riderName': riderName,
    'riderPhone': riderPhone,
    'contextType': contextType,
    'contextId': contextId,
    'contextCode': contextCode,
    'lastAt': iso(lastAt),
    'serverUnread': serverUnread,
    'hola': hola,
    'hasOlder': hasOlder,
  };
  factory ChatThread.fromJson(Json j) => ChatThread(
    id: j['id'],
    kind: j['kind'] ?? ChatKind.customerSalon,
    salonId: j['salonId'],
    customerId: j['customerId'],
    riderId: j['riderId'],
    salonName: j['salonName'] ?? '',
    customerName: j['customerName'] ?? '',
    customerPhone: j['customerPhone'] ?? '',
    riderName: j['riderName'] ?? '',
    riderPhone: j['riderPhone'] ?? '',
    contextType: j['contextType'],
    contextId: j['contextId'],
    contextCode: j['contextCode'] ?? '',
    lastAt: dt(j['lastAt'])!,
    serverUnread: j['serverUnread'] ?? 0,
    hola: j['hola'] ?? false,
    hasOlder: j['hasOlder'] ?? false,
  );
}

/// A photo in a message: on HOLA ([fileId]) and/or on this phone ([local],
/// a PhotoFiles name).
class ChatImage {
  final String? fileId;
  String? local;
  ChatImage({this.fileId, this.local});
  Json toJson() => {'fileId': fileId, 'local': local};
  factory ChatImage.fromJson(Json j) => ChatImage(fileId: j['fileId'], local: j['local']);
}

abstract final class MsgState {
  static const sent = 'SENT', sending = 'SENDING', failed = 'FAILED';
}

/// An order, return or voucher shared in a HOLA ↔ salon chat (contract
/// 0.25.0): a snapshot from when it was sent; tapping it opens the live record.
class MsgRef {
  static const order = 'ORDER', ret = 'RETURN', voucher = 'VOUCHER';
  final String type, id, code, title, status, subtitle;
  final int? amount;

  /// An ORDER that is a return's replacement.
  final bool replacement;
  const MsgRef({required this.type, required this.id, this.code = '', this.title = '', this.status = '', this.subtitle = '', this.amount, this.replacement = false});
  Json toJson() => {'type': type, 'id': id, 'code': code, 'title': title, 'status': status, 'subtitle': subtitle, 'amount': amount, if (replacement) 'replacement': true};
  factory MsgRef.fromJson(Json j) => MsgRef(
    type: j['type'],
    id: j['id'],
    code: j['code'] ?? '',
    title: j['title'] ?? '',
    status: j['status'] ?? '',
    subtitle: j['subtitle'] ?? '',
    amount: j['amount'] == null ? null : asInt(j['amount']),
    replacement: j['replacement'] == true,
  );
}

class ChatMessage {
  /// HOLA's id once sent; until then the [clientId].
  String id;
  final String threadId, senderId, side, clientId;
  String senderName;
  final String text;
  final List<ChatImage> images;

  /// A shared order, return or voucher (the message may have no text).
  final MsgRef? ref;
  DateTime at;

  /// The viewer has read it (their copy), or, for one's own messages, the
  /// other side has read it.
  bool read;

  /// For one's own messages: it reached the other side's phone (two grey
  /// ticks); [read] turns them blue.
  bool delivered;
  String state;

  ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.side,
    String? clientId,
    this.senderName = '',
    required this.text,
    List<ChatImage>? images,
    required this.at,
    this.read = false,
    this.delivered = false,
    this.ref,
    this.state = MsgState.sent,
  }) : clientId = clientId ?? id,
       images = images ?? [];

  bool get fromSalon => side == ChatSide.salon;

  Json toJson() => {
    'id': id,
    'threadId': threadId,
    'senderId': senderId,
    'side': side,
    'clientId': clientId,
    'senderName': senderName,
    'text': text,
    'images': [for (final i in images) i.toJson()],
    'at': iso(at),
    'read': read,
    if (delivered) 'delivered': true,
    if (ref != null) 'ref': ref!.toJson(),
    'state': state,
  };
  factory ChatMessage.fromJson(Json j) => ChatMessage(
    id: j['id'],
    threadId: j['threadId'],
    senderId: j['senderId'],
    // Older saves had fromSalon instead of side.
    side: j['side'] ?? (j['fromSalon'] == true ? ChatSide.salon : ChatSide.customer),
    clientId: j['clientId'],
    senderName: j['senderName'] ?? '',
    text: j['text'] ?? '',
    images: [for (final x in (j['images'] as List? ?? const [])) ChatImage.fromJson((x as Map).cast<String, dynamic>())],
    at: dt(j['at'])!,
    read: j['read'] ?? false,
    delivered: j['delivered'] ?? false,
    ref: j['ref'] == null ? null : MsgRef.fromJson(Map<String, dynamic>.from(j['ref'])),
    // A send that was cut off by closing the app is shown as failed (retry).
    state: j['state'] == MsgState.sending ? MsgState.failed : (j['state'] ?? MsgState.sent),
  );
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
