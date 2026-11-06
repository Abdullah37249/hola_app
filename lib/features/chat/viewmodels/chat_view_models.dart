import 'dart:async';
import 'dart:io';

import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/push/push_events.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';

/// How a conversation looks from the signed-in person's side.
class ThreadSummary {
  final ChatThread thread;

  /// The other party: the salon (for customers and riders), or the client or
  /// rider (for the salon).
  final String name, phone;

  /// The other party is a salon (shown with salon artwork).
  final bool salonSide;
  final int palette;

  /// "Rider" for a rider chat seen by the salon; empty otherwise.
  final String tag;

  /// "Booking HB-10001" / "Order HO-000010", or empty.
  final String about;
  final ChatMessage? last;
  final int unread;
  const ThreadSummary({
    required this.thread,
    required this.name,
    required this.phone,
    required this.salonSide,
    required this.palette,
    required this.tag,
    required this.about,
    required this.last,
    required this.unread,
  });
}

ThreadSummary summarize(ChatThread t, ChatRepository chat, SalonRepository salons) {
  final side = chat.mySide;
  final salon = salons.salon(t.salonId);
  final salonName = t.salonName.isNotEmpty ? t.salonName : (salon?.name ?? tr('Salon'));
  final String name, phone;
  final salonSide = side != ChatSide.salon;
  if (t.withHola && side == ChatSide.salon) {
    // The salon talks to HOLA's team.
    return ThreadSummary(thread: t, name: tr('HOLA team'), phone: '', salonSide: false, palette: 0, tag: 'HOLA', about: aboutLabel(t), last: chat.lastMessage(t.id), unread: chat.unread(t.id));
  }
  if (salonSide) {
    name = salonName;
    phone = salon?.phone ?? '';
  } else if (t.withRider) {
    name = t.riderName.isNotEmpty ? t.riderName : tr('Rider');
    phone = t.riderPhone;
  } else {
    name = t.customerName.isNotEmpty ? t.customerName : tr('Client');
    phone = t.customerPhone;
  }
  return ThreadSummary(
    thread: t,
    name: name,
    phone: phone,
    salonSide: salonSide,
    palette: salonSide ? (salon?.palette ?? t.salonId.hashCode.abs() % 6) : name.codeUnits.fold(0, (s, x) => s + x),
    tag: side == ChatSide.salon && t.withRider ? tr('Rider') : '',
    about: aboutLabel(t),
    last: chat.lastMessage(t.id),
    unread: chat.unread(t.id),
  );
}

/// "Booking HB-10001" or "Order HO-000010".
String aboutLabel(ChatThread t) => switch (t.contextType) {
  'APPOINTMENT' => t.contextCode.isEmpty ? tr('About a booking') : tr('Booking {code}', {'code': t.contextCode}),
  'ORDER' => t.contextCode.isEmpty ? tr('About an order') : tr('Order {code}', {'code': t.contextCode}),
  'RETURN' => t.contextCode.isEmpty ? tr('About a return') : tr('Return {code}', {'code': t.contextCode}),
  _ => '',
};

/// One conversation. While it's open, new messages are fetched every few
/// seconds and the moment a push for it arrives.
class ChatViewModel extends RepoViewModel {
  ChatViewModel(this.threadId, this.chat, this._salons) : super(chat) {
    _markRead();
    if (chat.live) {
      chat.syncThread(threadId).catchError((Object _) {});
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => chat.syncThread(threadId).catchError((Object _) {}));
      _pushes = pushEvents.stream.listen((_) => chat.syncThread(threadId).catchError((Object _) {}));
    }
    openThreadId = threadId;
  }
  final String threadId;
  final ChatRepository chat;
  final SalonRepository _salons;
  Timer? _poll;
  StreamSubscription<String>? _pushes;

  /// The conversation on screen, so its pushes don't also pop a banner.
  static String? openThreadId;

  ChatThread? get thread => chat.thread(threadId);
  ThreadSummary? get summary => thread == null ? null : summarize(thread!, chat, _salons);
  List<ChatMessage> get messages => chat.messages(threadId);
  String get mySide => chat.mySide;
  bool get canLoadOlder => thread?.hasOlder ?? false;

  @override
  void refresh() => _markRead();

  void _markRead() {
    if (chat.unread(threadId) == 0) return;
    // Out of the change callback: marking read is itself a change.
    scheduleMicrotask(() => chat.markRead(threadId));
  }

  Future<void> send(String text, List<String> images, {MsgRef? ref}) => chat.send(threadId, text: text, imagePaths: images, ref: ref);

  /// The salon can share its orders, returns and vouchers with HOLA here.
  bool get canShare => thread?.withHola == true && chat.mySide == ChatSide.salon;
  Future<void> retry(String id) => chat.retry(id);
  Future<bool> loadOlder() => chat.loadOlder(threadId);
  Future<File?> image(ChatImage i) => chat.imageFile(i);

  @override
  void dispose() {
    _poll?.cancel();
    _pushes?.cancel();
    if (openThreadId == threadId) openThreadId = null;
    super.dispose();
  }
}

/// The signed-in person's conversations, kept fresh while the list is open.
class InboxViewModel extends RepoViewModel {
  InboxViewModel(this.chat, this._salons) : super(chat) {
    if (chat.live) {
      pull().catchError((Object _) {});
      _poll = Timer.periodic(const Duration(seconds: 10), (_) => chat.sync().catchError((Object _) {}));
    }
  }
  final ChatRepository chat;
  final SalonRepository _salons;
  Timer? _poll;

  /// Salon only: 'all', 'clients' or 'riders'.
  String filter = 'all';
  void setFilter(String f) {
    filter = f;
    notify();
  }

  bool get isSalon => chat.mySide == ChatSide.salon;
  bool get hasRiders => chat.threads().any((t) => t.withRider);

  List<ThreadSummary> get threads => [
    for (final t in chat.threads())
      if (filter == 'all' || (filter == 'riders') == t.withRider) summarize(t, chat, _salons),
  ];

  int get unread => chat.unreadTotal;
  Future<void> pull() => chat.sync();

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

/// What the salon can share as a card in a HOLA chat: its orders,
/// replacement orders, returns and vouchers.
class ShareRefs {
  ShareRefs(this.trade, this.returns, this.salonId);
  final TradeRepository trade;
  final ReturnRepository returns;
  final String salonId;

  MsgRef _order(TradeOrder o) => MsgRef(
    type: MsgRef.order,
    id: o.id,
    code: o.code,
    title: o.replacementFor != null ? 'Replacement order' : 'Order',
    status: o.status,
    amount: o.total,
    subtitle: o.replacementFor != null ? 'For return ${o.replacementFor}' : '${o.lines.length} item${o.lines.length == 1 ? '' : 's'}',
    replacement: o.replacementFor != null,
  );

  List<MsgRef> get orders => [
    for (final o in trade.ordersForSalon(salonId))
      if (o.replacementFor == null) _order(o),
  ];
  List<MsgRef> get replacements => [
    for (final o in trade.ordersForSalon(salonId))
      if (o.replacementFor != null) _order(o),
  ];
  List<MsgRef> get returnRefs => [
    for (final r in returns.returns(salonId: salonId))
      MsgRef(type: MsgRef.ret, id: r.id, code: r.code, title: 'Return', status: r.status, amount: r.approvedAmount ?? r.amount, subtitle: 'Order ${r.orderCode}'),
  ];
  List<MsgRef> get vouchers => [
    for (final c in trade.coupons(salonId))
      MsgRef(type: MsgRef.voucher, id: c.id, code: c.code, title: c.title.isEmpty ? 'Voucher' : c.title, status: c.usedAt != null ? 'USED' : 'ACTIVE', subtitle: c.discountText),
  ];
}
