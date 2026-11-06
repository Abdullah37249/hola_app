import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/chat_view_models.dart';

/// One conversation, for a customer, a salon or a rider.
class ChatPage extends StatelessWidget {
  final String threadId;
  const ChatPage({super.key, required this.threadId});

  /// Opens the booking or order a conversation is about (set by the app, which
  /// knows every role's screens).
  static void Function(BuildContext context, NotifLink link)? openContext;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => ChatViewModel(threadId, c.read<ChatRepository>(), c.read<SalonRepository>()), child: const _Chat());
}

/// Finds or starts a conversation and opens it. A customer passes [salonId];
/// a salon passes [customerId] or [riderId]; a rider passes [salonId] and
/// [orderId]. [appointmentId] / [orderId] say what it's about.
Future<void> openChat(BuildContext context, {required String salonId, String? customerId, String? riderId, String? appointmentId, String? orderId}) async {
  ChatThread? t;
  final ok = await attempt(() async => t = await context.read<ChatRepository>().open(salonId: salonId, customerId: customerId, riderId: riderId, appointmentId: appointmentId, orderId: orderId));
  if (ok && t != null && context.mounted) pushPage(context, ChatPage(threadId: t!.id));
}

/// The salon's conversation with HOLA's team: general, or about one return.
Future<void> openHolaChat(BuildContext context, {required String salonId, String? returnId}) async {
  ChatThread? t;
  final ok = await attempt(() async => t = await context.read<ChatRepository>().openHola(salonId: salonId, returnId: returnId));
  if (ok && t != null && context.mounted) pushPage(context, ChatPage(threadId: t!.id));
}

/// The customer's general conversation with a salon.
Future<void> openSalonChat(BuildContext context, String salonId) => openChat(context, salonId: salonId);

class _Chat extends StatefulWidget {
  const _Chat();
  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final text = TextEditingController();
  final _photos = <String>[];
  bool _sending = false, _older = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  bool get _canSend => text.text.trim().isNotEmpty || _photos.isNotEmpty;

  Future<void> _send(ChatViewModel vm) async {
    if (!_canSend || _sending) return;
    final body = text.text.trim(), photos = [..._photos];
    // Clear at once: the message shows straight away as "sending".
    setState(() {
      _sending = true;
      text.clear();
      _photos.clear();
    });
    final ok = await attempt(() => vm.send(body, photos));
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) Sfx.soft();
  }

  /// In a HOLA chat the salon shares an order, return, replacement order or
  /// voucher as a card (the clip button; the camera only sends photos).
  Future<void> _share(ChatViewModel vm) async {
    final ref = await _pickRef(vm);
    if (ref == null || !mounted) return;
    final ok = await attempt(() => vm.send('', const [], ref: ref));
    if (ok) Sfx.soft();
  }

  Future<MsgRef?> _pickRef(ChatViewModel vm) {
    final refs = ShareRefs(context.read<TradeRepository>(), context.read<ReturnRepository>(), vm.thread!.salonId);
    var tab = 'orders';
    return showHSheet<MsgRef>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final list = switch (tab) {
            'repl' => refs.replacements,
            'returns' => refs.returnRefs,
            'vouchers' => refs.vouchers,
            _ => refs.orders,
          };
          return VStack(gap: 12, [
            SheetHead(tr('Share with HOLA'), sub: tr('HOLA sees it as a card and can open it.')),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (k, l) in [('orders', tr('Orders')), ('returns', tr('Return requests')), ('repl', tr('Replacement orders')), ('vouchers', tr('Vouchers'))]) ...[
                    HChip(l, on: tab == k, onTap: () => set(() => tab = k)),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            if (list.isEmpty)
              EmptyState(icon: 'box', title: tr('Nothing here yet'), text: tr('Orders, returns and vouchers of your salon show here.'))
            else
              Group(
                children: [
                  for (final r in list.take(30))
                    MRow(
                      icon: _refIcon(r),
                      title: '${tr(r.title)} ${r.code}'.trim(),
                      sub: [if (r.amount != null) rs(r.amount!), if (r.status.isNotEmpty) tr(_statusWord(r.status)), if (r.subtitle.isNotEmpty) r.subtitle].join(' · '),
                      onTap: () => Navigator.pop(ctx, r),
                    ),
                ],
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _attach() async {
    final left = 4 - _photos.length;
    if (left <= 0) {
      Fx.toast(tr('Send up to 4 photos at a time.'), icon: 'camera');
      return;
    }
    final source = await showHSheet<ImageSource>(
      context,
      (ctx) => VStack(gap: 10, [
        SheetHead(tr('Send a photo'), sub: tr('Up to {n} at a time.', {'n': 4})),
        HButton(tr('Choose from gallery'), icon: 'grid', block: true, onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        HButton(tr('Take a photo'), icon: 'camera', block: true, kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx, ImageSource.camera)),
      ]),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final picked = source == ImageSource.camera
        ? [if (await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 82) case final x?) x]
        : await picker.pickMultiImage(maxWidth: 1600, imageQuality: 82, limit: left > 1 ? left : null);
    if (picked.isEmpty || !mounted) return;
    setState(() => _photos.addAll(picked.take(left).map((x) => x.path)));
  }

  Future<void> _loadOlder(ChatViewModel vm) async {
    setState(() => _older = true);
    await attempt(vm.loadOlder);
    if (mounted) setState(() => _older = false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatViewModel>();
    final c = context.c;
    final top = MediaQuery.paddingOf(context).top;
    final msgs = vm.messages.reversed.toList();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final s = vm.summary;
    final t = vm.thread;
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          // header
          Container(
            padding: EdgeInsets.fromLTRB(8, top + 4, 12, 10),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                IconBtn(
                  'back',
                  onTap: () {
                    Sfx.back();
                    Navigator.of(context).maybePop();
                  },
                ),
                const SizedBox(width: 6),
                if (s != null) _Face(s, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s?.name ?? tr('Conversation'), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                      if (s != null && (s.tag.isNotEmpty || s.phone.isNotEmpty))
                        Text([if (s.tag.isNotEmpty) s.tag, if (s.phone.isNotEmpty) s.phone].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context)),
                    ],
                  ),
                ),
                if (s != null && s.phone.isNotEmpty) IconBtn('phone', onTap: () => _call(context, s.name, s.phone)),
              ],
            ),
          ),
          // What it's about: the booking or order, tap to open it.
          if (t != null && t.contextType != null && t.contextId != null)
            Material(
              color: c.brandSoft,
              child: InkWell(
                onTap: ChatPage.openContext == null
                    ? null
                    : () => ChatPage.openContext!(
                        context,
                        NotifLink(switch (t.contextType) {
                          'ORDER' => 'order',
                          'RETURN' => 'return',
                          _ => 'appointment',
                        }, t.contextId!),
                      ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kGutter, vertical: 10),
                  child: Row(
                    children: [
                      HIcon(
                        switch (t.contextType) {
                          'ORDER' => 'box',
                          'RETURN' => 'again',
                          _ => 'cal',
                        },
                        size: 16,
                        color: c.brandText,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          aboutLabel(t),
                          style: T.sm(context).copyWith(color: c.brandText, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (ChatPage.openContext != null) ...[Text(tr('Open'), style: T.cap(context).copyWith(color: c.brandText)), HIcon('chev', size: 14, color: c.brandText)],
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: msgs.isEmpty
                ? ListView(
                    children: [
                      EmptyState(
                        icon: 'msg',
                        title: tr('Say hello'),
                        text: switch (vm.mySide) {
                          ChatSide.customer => tr('Ask about services, prices, timings or your booking. The salon replies here and you get a notification.'),
                          ChatSide.rider => tr('Message the salon about this delivery: directions, timing or anything else.'),
                          _ => tr('Messages you send appear here, and you get a notification when they reply.'),
                        },
                      ),
                    ],
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 12),
                    itemCount: msgs.length + (vm.canLoadOlder ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == msgs.length) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Center(
                            child: _older
                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                : HButton(tr('Earlier messages'), small: true, kind: BtnKind.ghost, onTap: () => _loadOlder(vm)),
                          ),
                        );
                      }
                      final m = msgs[i];
                      final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                      final mine = m.side == vm.mySide;
                      return Column(
                        children: [
                          if (older == null || !sameDay(older.at, m.at)) _DaySep(m.at),
                          _Bubble(m, mine: mine, tight: older != null && older.side == m.side && sameDay(older.at, m.at), vm: vm),
                        ],
                      );
                    },
                  ),
          ),
          // composer
          Container(
            // Above the keyboard: no extra gesture-bar padding; otherwise clear it.
            padding: EdgeInsets.fromLTRB(10, 10, 10, 10 + (keyboard ? 0 : MediaQuery.paddingOf(context).bottom)),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_photos.isNotEmpty)
                  SizedBox(
                    height: 76,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 10),
                      children: [
                        for (final p in _photos)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(File(p), width: 66, height: 66, fit: BoxFit.cover, cacheWidth: 200),
                                ),
                                Positioned(
                                  right: -6,
                                  top: -6,
                                  child: Tap(
                                    onTap: () => setState(() => _photos.remove(p)),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                                      alignment: Alignment.center,
                                      child: HIcon('x', size: 12, color: c.surface),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (vm.canShare) ...[
                      Tap(
                        key: const ValueKey('chat-share'),
                        onTap: () => _share(vm),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: c.bg2, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: HIcon('attach', size: 20, color: c.brandText),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Tap(
                      key: const ValueKey('chat-photo'),
                      onTap: _attach,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: c.bg2, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: HIcon('camera', size: 20, color: c.brandText),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: text,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(fontFamily: T.f, fontSize: 16, color: c.ink),
                        decoration: InputDecoration(
                          hintText: tr('Write a message'),
                          hintStyle: TextStyle(color: c.subtle),
                          counterText: '',
                          filled: true,
                          fillColor: c.bg2,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _canSend ? 1 : .4,
                      child: Tap(
                        onTap: _canSend ? () => _send(vm) : null,
                        sound: false,
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: const BoxDecoration(gradient: G.btn, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Padding(
                                  padding: EdgeInsets.only(left: 2),
                                  child: HIcon('nav', size: 20, color: Colors.white),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _call(BuildContext context, String name, String phone) => showHSheet(
    context,
    (ctx) => VStack(gap: 16, [
      SheetHead(tr('Call {name}', {'name': name})),
      SelectableText(phone, style: T.display(ctx)),
      HButton(
        tr('Copy number'),
        icon: 'clip',
        block: true,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: phone));
          if (ctx.mounted) Navigator.pop(ctx);
          Fx.toast(tr('Number copied'));
        },
      ),
    ]),
  );
}

/// Salon artwork for a salon, initials for a person.
class _Face extends StatelessWidget {
  const _Face(this.s, {required this.size});
  final ThreadSummary s;
  final double size;
  @override
  Widget build(BuildContext context) => s.salonSide
      ? ClipRRect(
          borderRadius: BorderRadius.circular(size * .3),
          child: SizedBox(
            width: size,
            height: size,
            child: SalonArt(s.palette, n: 2, radius: size * .3, name: s.name),
          ),
        )
      : Avatar(s.name, size: size, k: s.palette);
}

class _DaySep extends StatelessWidget {
  final DateTime at;
  const _DaySep(this.at);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: context.c.bg2, borderRadius: BorderRadius.circular(999)),
        child: Text(dayLabel(at, today), style: T.cap(context).copyWith(fontWeight: FontWeight.w600)),
      ),
    ),
  );
}

class _Bubble extends StatelessWidget {
  final ChatMessage m;
  final bool mine, tight;
  final ChatViewModel vm;
  const _Bubble(this.m, {required this.mine, required this.tight, required this.vm});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = const Radius.circular(18);
    final failed = m.state == MsgState.failed, sending = m.state == MsgState.sending;
    final fg = mine ? Colors.white : c.ink;
    final bubble = Container(
      padding: EdgeInsets.fromLTRB(m.images.isEmpty ? 14 : 4, m.images.isEmpty ? 10 : 4, m.images.isEmpty ? 14 : 4, 8),
      decoration: BoxDecoration(
        gradient: mine && !failed ? G.btn : null,
        color: failed ? c.badSoft : (mine ? null : c.surface),
        borderRadius: BorderRadius.only(topLeft: r, topRight: r, bottomLeft: mine ? r : const Radius.circular(6), bottomRight: mine ? const Radius.circular(6) : r),
        boxShadow: mine ? null : c.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.ref != null) RefCard(m.ref!, mine: mine),
          if (m.images.isNotEmpty) _Photos(m.images, vm: vm),
          if (m.text.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(m.images.isEmpty ? 0 : 10, m.images.isEmpty ? 0 : 8, m.images.isEmpty ? 0 : 10, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  m.text,
                  style: T.body(context).copyWith(color: failed ? c.badInk : fg, height: 22 / 16),
                ),
              ),
            ),
          const SizedBox(height: 2),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: m.images.isEmpty ? 0 : 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (failed) ...[
                  HIcon('alert', size: 12, color: c.badInk),
                  const SizedBox(width: 4),
                  Text(tr('Not sent · tap to retry'), style: T.cap(context).copyWith(fontSize: 11, color: c.badInk)),
                  const SizedBox(width: 6),
                ],
                Text(fmtTime(m.at), style: T.cap(context).copyWith(fontSize: 11, color: failed ? c.badInk : (mine ? Colors.white70 : c.subtle))),
                if (mine && !failed) ...[const SizedBox(width: 4), sending ? const HIcon('clock', size: 12, color: Colors.white70) : MsgTicks(m)],
              ],
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: tight ? 3 : 10, left: mine ? 48 : 0, right: mine ? 0 : 48),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Reveal(
          child: failed ? GestureDetector(onTap: () => attempt(() => vm.retry(m.id)), child: bubble) : bubble,
        ),
      ),
    );
  }
}

/// One to four photos in a bubble; tap one to see it full screen.
class _Photos extends StatelessWidget {
  const _Photos(this.images, {required this.vm});
  final List<ChatImage> images;
  final ChatViewModel vm;
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width * .62;
    Widget one(ChatImage i, double width, double height) => GestureDetector(
      onTap: () {
        dropFocus();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _PhotoViewer(images: images, start: images.indexOf(i), vm: vm),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: width,
          height: height,
          child: _ChatPhoto(i, vm: vm, fit: BoxFit.cover),
        ),
      ),
    );
    if (images.length == 1) return one(images.first, w, w * 1.1);
    final half = (w - 4) / 2;
    return SizedBox(
      width: w,
      child: Wrap(spacing: 4, runSpacing: 4, children: [for (final i in images) one(i, half, half)]),
    );
  }
}

/// A chat photo from this phone, or downloaded from HOLA on first view.
class _ChatPhoto extends StatefulWidget {
  const _ChatPhoto(this.image, {required this.vm, this.fit = BoxFit.cover});
  final ChatImage image;
  final ChatViewModel vm;
  final BoxFit fit;
  @override
  State<_ChatPhoto> createState() => _ChatPhotoState();
}

class _ChatPhotoState extends State<_ChatPhoto> {
  late Future<File?> _file = widget.vm.image(widget.image);

  @override
  void didUpdateWidget(covariant _ChatPhoto old) {
    super.didUpdateWidget(old);
    if (old.image.fileId != widget.image.fileId || old.image.local != widget.image.local) _file = widget.vm.image(widget.image);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, snap) {
      final f = snap.data;
      if (f != null) return Image.file(f, fit: widget.fit, cacheWidth: widget.fit == BoxFit.contain ? null : 700, gaplessPlayback: true);
      return Container(
        color: context.c.bg2,
        alignment: Alignment.center,
        child: snap.connectionState == ConnectionState.done
            ? GestureDetector(
                onTap: () => setState(() => _file = widget.vm.image(widget.image)),
                child: HIcon('camera', size: 22, color: context.c.subtle),
              )
            : const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    },
  );
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.images, required this.start, required this.vm});
  final List<ChatImage> images;
  final int start;
  final ChatViewModel vm;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        PageView(
          controller: PageController(initialPage: start),
          children: [
            for (final i in images)
              InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: _ChatPhoto(i, vm: vm, fit: BoxFit.contain),
                ),
              ),
          ],
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 8,
          child: IconBtn('x', onBand: true, onTap: () => Navigator.of(context).pop()),
        ),
      ],
    ),
  );
}

/// WhatsApp-style ticks on one's own message: one grey tick once HOLA has
/// it, two grey once it reached the other phone, two blue once read.
class MsgTicks extends StatelessWidget {
  const MsgTicks(this.m, {super.key});
  final ChatMessage m;
  static const _readBlue = Color(0xFF7FE3FF);
  @override
  Widget build(BuildContext context) {
    final two = m.read || m.delivered;
    final color = m.read ? _readBlue : Colors.white60;
    final tick = HIcon('check', size: 12, stroke: 2.4, color: color);
    return Semantics(
      label: m.read
          ? tr('Read')
          : m.delivered
          ? tr('Delivered')
          : tr('Sent'),
      child: SizedBox(
        width: two ? 17 : 12,
        height: 12,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            tick,
            if (two) Positioned(left: 5, child: tick),
          ],
        ),
      ),
    );
  }
}

String _refIcon(MsgRef r) => switch (r.type) {
  MsgRef.ret => 'again',
  MsgRef.voucher => 'cash',
  _ => r.replacement ? 'again' : 'box',
};

/// A status code in words (English; shown through tr()).
String _statusWord(String s) => switch (s) {
  'PLACED' => 'Placed',
  'UNDER_REVIEW' => 'Under review',
  'APPROVED' || 'PROCESSING' => 'Approved',
  'DISPATCHED' => 'Dispatched',
  'OUT_FOR_DELIVERY' => 'Out for delivery',
  'DELIVERED' => 'Delivered',
  'CONFIRMED' => 'Receipt confirmed',
  'CANCELLED' => 'Cancelled',
  'REQUESTED' => 'Return requested',
  'RESPONSE_SENT' => 'HOLA replied',
  'AWAITING_SALON_CONFIRMATION' => 'Your answer needed',
  'PICKUP_ASSIGNED' => 'Pickup assigned',
  'REPLACEMENT_ORDER_CREATED' => 'Replacement on its way',
  'COMPLETED' => 'Completed',
  'REJECTED' => 'Rejected',
  'ACTIVE' => 'Active',
  'USED' => 'Used',
  'EXPIRED' => 'Expired',
  _ => s,
};

/// An order, return or voucher shared in a HOLA chat; tap to open it.
class RefCard extends StatelessWidget {
  const RefCard(this.r, {super.key, required this.mine});
  final MsgRef r;
  final bool mine;

  /// A shared voucher's minimum order, from the salon's own coupons (0 = none).
  int _minOrder(BuildContext context) {
    if (r.type != MsgRef.voucher) return 0;
    final salonId = context.read<AuthRepository>().current?.salonId;
    if (salonId == null) return 0;
    final c = context.read<TradeRepository>().coupons(salonId).where((x) => x.code == r.code).firstOrNull;
    return c?.minOrder ?? 0;
  }

  void _open(BuildContext context) {
    final min = _minOrder(context);
    switch (r.type) {
      case MsgRef.order:
        ChatPage.openContext?.call(context, NotifLink('order', r.id));
      case MsgRef.ret:
        ChatPage.openContext?.call(context, NotifLink('return', r.id));
      default:
        showHSheet<void>(
          context,
          (ctx) => VStack(gap: 10, [
            SheetHead(tr(r.title.isEmpty ? 'Voucher' : r.title)),
            SelectableText(r.code, style: T.display(ctx)),
            if (r.subtitle.isNotEmpty) Text(r.subtitle, style: T.body(ctx)),
            if (r.amount != null) KV(tr('Value'), rs(r.amount!)),
            if (min > 0) KV(tr('Minimum order'), rs(min)),
            if (r.status.isNotEmpty) KV(tr('Status'), tr(_statusWord(r.status))),
            HButton(
              tr('Copy code'),
              icon: 'clip',
              kind: BtnKind.secondary,
              block: true,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: r.code));
                if (ctx.mounted) Navigator.pop(ctx);
                Fx.toast(tr('Voucher code copied'));
              },
            ),
          ]),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = mine ? Colors.white : c.ink;
    final sub = mine ? Colors.white70 : c.muted;
    return Tap(
      onTap: () => _open(context),
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? Colors.white.withValues(alpha: .14) : c.bg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: mine ? Colors.white24 : c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: mine ? Colors.white24 : c.brandSoft, borderRadius: BorderRadius.circular(10)),
              alignment: Alignment.center,
              child: HIcon(_refIcon(r), size: 20, color: mine ? Colors.white : c.brandText),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${tr(r.title)} ${r.code}'.trim(),
                    // Two lines so the code (the part that matters) isn't cut off.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.ttl(context).copyWith(color: fg, fontSize: 15),
                  ),
                  Text(
                    [if (r.amount != null) rs(r.amount!), if (r.status.isNotEmpty) tr(_statusWord(r.status))].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.cap(context).copyWith(color: sub),
                  ),
                  if (r.subtitle.isNotEmpty)
                    Text(
                      r.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.cap(context).copyWith(color: sub),
                    ),
                  // Its own line, so it's never the part cut off.
                  if (_minOrder(context) case final min when min > 0)
                    Text(
                      tr('Min. order {amount}', {'amount': rsShort(min)}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.cap(context).copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            HIcon('chev', size: 16, color: sub),
          ],
        ),
      ),
    );
  }
}
