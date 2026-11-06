import 'dart:io';
import 'dart:math';

import '../../core/l10n/l10n.dart';
import '../../core/network/api.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/photo_files.dart';
import '../../domain/entities/entities.dart';
import '../../domain/entities/json.dart' show asInt;
import '../../domain/repositories/repositories.dart';
import 'local_auth_repository.dart';

/// Chat for customers, salons and riders.
///
/// With HOLA's chat API ([chatLive], contract 0.17.0) every conversation and
/// message lives on the server: the app mirrors them here (so history opens
/// instantly and offline), sends through POST …/messages with photos uploaded
/// as `chat_image` files, and catches up with `?after=` while a chat is open
/// and whenever a `chat_message` push arrives. Without it (tests, or before
/// the API is live) conversations stay on this phone.
class LocalChatRepository extends LocalRepository implements ChatRepository {
  LocalChatRepository(super.db, {this.api}) {
    // A new account starts its conversation list from scratch, not from the
    // last account's "updated since" point (that hid all older threads).
    db.onWipe(() => _since = null);
  }
  final HolaApi? api;

  /// Switched on once HOLA confirms the chat contract on staging.
  static bool chatLive = true; // contract 0.17.0

  @override
  bool get live => api != null && chatLive;

  @override
  String get mySide => switch (me?.role) {
    Role.salonOwner || Role.salonStaff => ChatSide.salon,
    Role.rider => ChatSide.rider,
    Role.salesOfficer => ChatSide.hola,
    _ => ChatSide.customer,
  };

  bool _mine(ChatThread t) {
    final m = me;
    if (m == null) return false;
    return switch (m.role) {
      Role.salonOwner || Role.salonStaff => t.salonId == m.salonId,
      Role.rider => t.riderId == m.id,
      Role.customer => t.customerId == m.id,
      Role.salesOfficer => t.withHola,
      _ => false,
    };
  }

  @override
  List<ChatThread> threads() => db.threads.where((t) => _mine(t) && (t.hola || db.messages.any((m) => m.threadId == t.id))).toList()..sort((a, b) => b.lastAt.compareTo(a.lastAt));

  @override
  ChatThread? thread(String id) => db.threads.where((t) => t.id == id).firstOrNull;

  ChatThread _thread(String id) => thread(id) ?? (throw DomainError(tr('Conversation not found.')));

  @override
  List<ChatMessage> messages(String threadId) => db.messages.where((m) => m.threadId == threadId).toList()..sort((a, b) => a.at.compareTo(b.at));

  @override
  ChatMessage? lastMessage(String threadId) {
    ChatMessage? last;
    for (final m in db.messages) {
      if (m.threadId == threadId && (last == null || !m.at.isBefore(last.at))) last = m;
    }
    return last;
  }

  @override
  int unread(String threadId) {
    final local = db.messages.where((m) => m.threadId == threadId && m.side != mySide && !m.read).length;
    final t = thread(threadId);
    return t != null && t.hola && t.serverUnread > local ? t.serverUnread : local;
  }

  @override
  int get unreadTotal => threads().fold(0, (n, t) => n + unread(t.id));

  // ── starting a conversation ──

  @override
  Future<ChatThread> open({required String salonId, String? customerId, String? riderId, String? appointmentId, String? orderId}) async {
    final m = requireMe;
    final side = mySide;
    if (side == ChatSide.customer) customerId = m.id;
    if (side == ChatSide.rider) riderId = m.id;
    if (side == ChatSide.salon && m.salonId != salonId) throw DomainError(tr('Not your salon.'));
    if (customerId == null && riderId == null) throw DomainError(tr('Choose who to message.'));
    if (riderId != null && orderId == null) throw DomainError(tr('Rider chats are about an order.'));
    final ctxType = appointmentId != null
        ? 'APPOINTMENT'
        : orderId != null
        ? 'ORDER'
        : null;
    final ctxId = appointmentId ?? orderId;

    if (live) {
      final res = await _call(
        () => api!.post('/conversations', {
          'salonId': salonId,
          'customerId': ?(side == ChatSide.salon ? customerId : null),
          'riderId': ?(side == ChatSide.salon ? riderId : null),
          'appointmentId': ?appointmentId,
          'orderId': ?orderId,
        }),
      );
      final t = _mirrorThread(_data(res));
      db.commit();
      return t;
    }

    final existing = db.threads.where((t) => t.salonId == salonId && t.customerId == customerId && t.riderId == riderId && t.contextId == ctxId && !t.hola).firstOrNull;
    if (existing != null) return existing;
    final salon = db.salons.where((s) => s.id == salonId).firstOrNull ?? (throw DomainError(tr('Salon not found.')));
    final cust = customerId == null ? null : db.accounts.where((a) => a.id == customerId).firstOrNull;
    final rider = riderId == null ? null : db.accounts.where((a) => a.id == riderId).firstOrNull;
    final t = ChatThread(
      id: db.newId(),
      kind: riderId != null ? ChatKind.riderSalon : ChatKind.customerSalon,
      salonId: salonId,
      customerId: customerId,
      riderId: riderId,
      salonName: salon.name,
      customerName: cust?.name ?? '',
      customerPhone: cust?.phone ?? '',
      riderName: rider?.name ?? '',
      riderPhone: rider?.phone ?? '',
      contextType: ctxType,
      contextId: ctxId,
      contextCode: _codeOf(ctxType, ctxId),
      lastAt: now(),
    );
    db.threads.add(t);
    db.commit();
    return t;
  }

  /// HOLA ↔ salon chat is live on the server (0.23.0).
  static bool holaChatLive = true;

  @override
  bool get holaChat => api == null || holaChatLive;

  @override
  Future<ChatThread> openHola({required String salonId, String? returnId}) async {
    final m = requireMe;
    if (mySide == ChatSide.salon && m.salonId != salonId) throw DomainError(tr('Not your salon.'));
    if (mySide != ChatSide.salon && mySide != ChatSide.hola) throw DomainError(tr("Your account can't do that."));
    final ctxType = returnId == null ? null : 'RETURN';
    if (!holaChat) throw DomainError(tr('Chat with HOLA opens soon.'));
    if (live && (db.salons.where((s) => s.id == salonId).firstOrNull?.hola ?? false)) {
      final res = await _call(() => api!.post('/conversations', {'kind': ChatKind.holaSalon, 'salonId': salonId, 'returnId': ?returnId}));
      final t = _mirrorThread(_data(res));
      db.commit();
      return t;
    }
    final existing = db.threads.where((t) => t.withHola && t.salonId == salonId && t.contextId == returnId).firstOrNull;
    if (existing != null) return existing;
    final salon = db.salons.where((s) => s.id == salonId).firstOrNull ?? (throw DomainError(tr('Salon not found.')));
    final t = ChatThread(
      id: db.newId(),
      kind: ChatKind.holaSalon,
      salonId: salonId,
      salonName: salon.name,
      contextType: ctxType,
      contextId: returnId,
      contextCode: _codeOf(ctxType, returnId),
      lastAt: now(),
    );
    db.threads.add(t);
    db.commit();
    return t;
  }

  String _codeOf(String? type, String? id) => switch (type) {
    'APPOINTMENT' => db.appointments.where((a) => a.id == id).firstOrNull?.code ?? '',
    'ORDER' => db.orders.where((o) => o.id == id).firstOrNull?.code ?? '',
    'RETURN' => db.returns.where((r) => r.id == id).firstOrNull?.code ?? '',
    _ => '',
  };

  // ── sending ──

  @override
  Future<void> send(String threadId, {String text = '', List<String> imagePaths = const [], MsgRef? ref}) async {
    final t = _thread(threadId);
    final m = requireMe;
    if (!_mine(t)) throw DomainError(tr('Not your conversation.'));
    final body = text.trim();
    if (body.isEmpty && imagePaths.isEmpty && ref == null) return;
    if (ref != null && !t.withHola) throw DomainError(tr('Orders and returns can be shared only with HOLA.'));
    if (body.length > 2000) throw DomainError(tr('Messages can be up to 2000 characters.'));
    if (imagePaths.length > 4) throw DomainError(tr('Send up to 4 photos at a time.'));
    final images = <ChatImage>[];
    for (final p in imagePaths) {
      images.add(ChatImage(local: PhotoFiles.available ? await PhotoFiles.keep(p) : p));
    }
    final id = _uuid();
    final msg = ChatMessage(
      id: id,
      threadId: t.id,
      senderId: m.id,
      side: mySide,
      senderName: m.name,
      text: body,
      images: images,
      ref: ref,
      at: now(),
      state: live && t.hola ? MsgState.sending : MsgState.sent,
      delivered: !(live && t.hola),
    ); // on-device: the other side's "phone" is this one
    db.messages.add(msg);
    t.lastAt = msg.at;
    db.commit();
    if (live && t.hola) {
      await _deliver(msg);
    } else {
      _notifyLocally(t, msg);
    }
  }

  @override
  Future<void> retry(String messageId) async {
    final msg = db.messages.where((m) => m.id == messageId).firstOrNull;
    if (msg == null || msg.state != MsgState.failed) return;
    msg
      ..state = MsgState.sending
      ..at = now();
    db.commit();
    await _deliver(msg);
  }

  /// Uploads the photos, then posts the message; HOLA's copy replaces ours.
  Future<void> _deliver(ChatMessage msg) async {
    try {
      final fileIds = <String>[];
      for (final img in msg.images) {
        if (img.fileId != null) {
          fileIds.add(img.fileId!);
          continue;
        }
        final f = img.local == null ? null : (PhotoFiles.file(img.local) ?? File(img.local!));
        if (f == null || !f.existsSync()) continue;
        final bytes = await f.readAsBytes();
        final png = img.local!.toLowerCase().endsWith('.png');
        final id = await api!.uploadFile(bytes, contentType: png ? 'image/png' : 'image/jpeg', purpose: 'chat_image', fileName: 'chat.${png ? 'png' : 'jpg'}');
        final i = msg.images.indexOf(img);
        msg.images[i] = ChatImage(fileId: id, local: img.local);
        fileIds.add(id);
      }
      final res = await api!.post('/conversations/${msg.threadId}/messages', {
        if (msg.text.isNotEmpty) 'body': msg.text,
        if (fileIds.isNotEmpty) 'fileIds': fileIds,
        'clientId': msg.clientId,
        if (msg.ref != null) 'ref': {'type': msg.ref!.type, 'id': msg.ref!.id},
      });
      _mirrorMessage(_data(res), msg.threadId);
    } catch (e) {
      msg.state = MsgState.failed;
      db.commit();
      throw e is ApiError ? apiToDomain(e) : DomainError(tr('Could not send. Tap the message to try again.'));
    }
    db.commit();
  }

  /// On this phone only: the other side gets an in-app notification.
  void _notifyLocally(ChatThread t, ChatMessage msg) {
    final preview = msg.text.isNotEmpty ? msg.text : (msg.ref != null ? '${msg.ref!.title} ${msg.ref!.code}'.trim() : tr('Photo'));
    final link = NotifLink('chat', t.id);
    if (msg.side == ChatSide.salon) {
      final to = t.withRider ? t.riderId : t.customerId;
      if (to != null) db.notify(to, '{salon}', '{text}', args: {'salon': t.salonName, 'text': preview}, icon: 'msg', link: link);
    } else {
      db.notifySalon(t.salonId, 'Message from {name}', '{text}', args: {'name': msg.senderName, 'text': preview}, icon: 'msg', link: link);
    }
    db.commit();
  }

  // ── reading ──

  @override
  Future<void> markRead(String threadId) async {
    final t = thread(threadId);
    if (t == null) return;
    final theirs = db.messages.where((m) => m.threadId == threadId && m.side != mySide && !m.read).toList();
    if (theirs.isEmpty && t.serverUnread == 0) return;
    for (final m in theirs) {
      m.read = true;
    }
    final hadUnread = t.serverUnread > 0;
    t.serverUnread = 0;
    db.commit();
    if (live && t.hola && (theirs.isNotEmpty || hadUnread)) {
      final last = messages(threadId).where((m) => m.side != mySide && m.state == MsgState.sent).lastOrNull;
      if (last == null) return;
      try {
        await api!.post('/conversations/$threadId/read', {'upToMessageId': last.id});
      } catch (_) {
        // Next time the chat opens it tries again.
      }
    }
  }

  // ── HOLA sync ──

  DateTime? _since;
  Future<void>? _syncing;
  final _threadSyncs = <String, Future<void>>{};

  @override
  Future<void> sync() => !live ? Future.value() : (_syncing ??= _sync().whenComplete(() => _syncing = null));

  Future<void> _sync() async {
    final started = DateTime.now().toUtc();
    for (var page = 1, pages = 1; page <= pages && page <= 10; page++) {
      final res = await api!.get('/conversations', query: {'page': '$page', 'pageSize': '50', if (_since != null) 'updatedSince': _since!.toIso8601String()});
      final list = res is Map ? (res['data'] as List? ?? const []) : res as List;
      if (res is Map) pages = asInt((res['meta'] as Map?)?['totalPages'], 1);
      for (final j in list.cast<Map>()) {
        _mirrorThread(j.cast<String, dynamic>());
      }
    }
    _since = started.subtract(const Duration(seconds: 5));
    db.commit();
  }

  @override
  Future<void> syncThread(String threadId) {
    final t = thread(threadId);
    if (!live || t == null || !t.hola) return Future.value();
    return _threadSyncs[threadId] ??= _syncThread(t).whenComplete(() => _threadSyncs.remove(threadId));
  }

  /// No cursor: HOLA returns the newest page. With `after`: everything since
  /// the newest message this phone has, page by page.
  Future<void> _syncThread(ChatThread t) async {
    var after = messages(t.id).where((m) => m.state == MsgState.sent).lastOrNull?.id;
    final first = after == null;
    // Read receipts: `after` only brings newer messages, so while any of ours
    // is still unread, refresh the newest page to pick up its readAt.
    if (!first && messages(t.id).any((m) => m.side == mySide && m.state == MsgState.sent && !m.read)) {
      final res = await api!.get('/conversations/${t.id}/messages', query: {'limit': '50'});
      for (final j in (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<Map>()) {
        _mirrorMessage(j.cast<String, dynamic>(), t.id);
      }
    }
    for (var round = 0; round < 10; round++) {
      final res = await api!.get('/conversations/${t.id}/messages', query: {'limit': '50', 'after': ?after});
      final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<Map>();
      for (final j in list) {
        _mirrorMessage(j.cast<String, dynamic>(), t.id);
      }
      if (first) t.hasOlder = list.length >= 50;
      if (first || list.length < 50) break;
      after = '${list.last['id']}';
    }
    db.commit();
  }

  @override
  Future<bool> loadOlder(String threadId) async {
    final t = thread(threadId);
    if (!live || t == null || !t.hola || !t.hasOlder) return false;
    final first = messages(threadId).where((m) => m.state == MsgState.sent).firstOrNull;
    if (first == null) return false;
    final res = await _call(() => api!.get('/conversations/$threadId/messages', query: {'limit': '50', 'before': first.id}));
    final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<Map>();
    for (final j in list) {
      _mirrorMessage(j.cast<String, dynamic>(), threadId);
    }
    t.hasOlder = list.length >= 50;
    db.commit();
    return list.isNotEmpty;
  }

  // ── photos ──

  final _downloads = <String, Future<File?>>{};

  @override
  Future<File?> imageFile(ChatImage image) async {
    final local = image.local == null ? null : (PhotoFiles.file(image.local) ?? (File(image.local!).existsSync() ? File(image.local!) : null));
    if (local != null) return local;
    final id = image.fileId;
    if (id == null || api == null) return null;
    final name = 'chat_$id';
    final cached = PhotoFiles.file(name);
    if (cached != null) {
      image.local = name;
      return cached;
    }
    return _downloads[id] ??= () async {
      try {
        final f = await PhotoFiles.write(name, await api!.bytes('/files/$id/content'));
        if (f != null) image.local = name;
        return f;
      } catch (_) {
        return null;
      } finally {
        _downloads.remove(id);
      }
    }();
  }

  // ── mirroring HOLA's views ──

  J _data(Object? res) => res is Map ? ((res['data'] is Map ? res['data'] : res) as Map).cast<String, dynamic>() : <String, dynamic>{};

  Future<Object?> _call(Future<Object?> Function() f) async {
    try {
      return await f();
    } on ApiError catch (e) {
      throw apiToDomain(e);
    }
  }

  ChatThread _mirrorThread(J j) {
    final id = '${j['id']}';
    Map p(String k) => j[k] is Map ? j[k] as Map : const {};
    final salon = p('salon'), cust = p('customer'), rider = p('rider'), ctx = p('context');
    final old = thread(id);
    final t = ChatThread(
      id: id,
      kind: '${j['kind'] ?? (rider.isNotEmpty ? ChatKind.riderSalon : ChatKind.customerSalon)}',
      salonId: '${salon['id'] ?? j['salonId'] ?? ''}',
      customerId: (cust['id'] ?? j['customerId']) as String?,
      riderId: (rider['id'] ?? j['riderId']) as String?,
      salonName: '${salon['name'] ?? old?.salonName ?? ''}',
      customerName: '${cust['fullName'] ?? cust['name'] ?? old?.customerName ?? ''}',
      customerPhone: '${cust['phone'] ?? old?.customerPhone ?? ''}',
      riderName: '${rider['fullName'] ?? rider['name'] ?? old?.riderName ?? ''}',
      riderPhone: '${rider['phone'] ?? old?.riderPhone ?? ''}',
      contextType: ctx['type'] as String?,
      contextId: ctx['id'] as String?,
      contextCode: '${ctx['code'] ?? ''}',
      lastAt: DateTime.tryParse('${j['updatedAt'] ?? j['createdAt'] ?? ''}')?.toLocal() ?? old?.lastAt ?? now(),
      serverUnread: asInt(j['unreadCount'], 0),
      hola: true,
      hasOlder: old?.hasOlder ?? false,
    );
    final at = db.threads.indexWhere((x) => x.id == id);
    at < 0 ? db.threads.add(t) : db.threads[at] = t;
    if (j['lastMessage'] is Map) _mirrorMessage((j['lastMessage'] as Map).cast<String, dynamic>(), id);
    // HOLA says nothing is unread: everything they sent has been read,
    // perhaps on another phone.
    if (t.serverUnread == 0) {
      for (final m in db.messages) {
        if (m.threadId == id && m.side != mySide && m.state == MsgState.sent) m.read = true;
      }
    }
    return t;
  }

  ChatMessage _mirrorMessage(J j, String threadId) {
    final id = '${j['id']}';
    final clientId = j['clientId'] as String?;
    final sender = j['sender'] is Map ? j['sender'] as Map : const {};
    final senderId = '${sender['id'] ?? ''}';
    final side = '${sender['side'] ?? ChatSide.customer}';
    // Ours already (by HOLA id, or the copy we sent under clientId).
    final old = db.messages.where((m) => m.id == id || (clientId != null && m.clientId == clientId)).firstOrNull;
    final atts = (j['attachments'] as List? ?? const []).cast<Map>();
    final images = [
      for (final a in atts)
        ChatImage(
          fileId: '${a['fileId'] ?? a['id']}',
          // Keep the photo we already have on this phone.
          local: old?.images.where((i) => i.fileId == '${a['fileId'] ?? a['id']}').firstOrNull?.local ?? old?.images.elementAtOrNull(atts.indexOf(a))?.local,
        ),
    ];
    final mine = side == mySide;
    final msg = ChatMessage(
      id: id,
      threadId: threadId,
      senderId: senderId,
      side: side,
      clientId: clientId ?? id,
      senderName: '${sender['fullName'] ?? sender['name'] ?? ''}',
      text: '${j['body'] ?? ''}',
      images: images,
      at: DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal() ?? old?.at ?? now(),
      // Ours: read by them. Theirs: read here, or on any of our devices.
      read: j['readAt'] != null || (!mine && (old?.read ?? false)),
      delivered: j['deliveredAt'] != null || j['readAt'] != null,
      ref: _ref(j['ref']) ?? old?.ref,
    );
    final at = old == null ? -1 : db.messages.indexOf(old);
    at < 0 ? db.messages.add(msg) : db.messages[at] = msg;
    final t = thread(threadId);
    if (t != null && msg.at.isAfter(t.lastAt)) t.lastAt = msg.at;
    return msg;
  }

  /// A shared card in HOLA's message (0.25.0).
  static MsgRef? _ref(Object? v) {
    if (v is! Map || v['id'] == null) return null;
    return MsgRef(
      type: '${v['type']}',
      id: '${v['id']}',
      code: '${v['code'] ?? ''}',
      title: '${v['title'] ?? ''}',
      status: '${v['status'] ?? ''}',
      subtitle: '${v['subtitle'] ?? ''}',
      amount: v['amount'] == null ? null : (double.tryParse('${v['amount']}')?.round()),
      replacement: v['replacement'] == true,
    );
  }

  static final _rand = Random.secure();

  /// A v4 uuid; local message ids start as this clientId.
  static String _uuid() {
    final b = List<int>.generate(16, (_) => _rand.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    final x = [for (var i = 0; i < 16; i++) h(i)].join();
    return '${x.substring(0, 8)}-${x.substring(8, 12)}-${x.substring(12, 16)}-${x.substring(16, 20)}-${x.substring(20)}';
  }
}
