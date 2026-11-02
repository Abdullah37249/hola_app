import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/chat_view_models.dart';

/// A conversation between a customer and a salon. [asSalon] = viewing as the salon.
class ChatPage extends StatelessWidget {
  final String threadId;
  final bool asSalon;
  const ChatPage({super.key, required this.threadId, required this.asSalon});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => ChatViewModel(threadId, asSalon, c.read<EngagementRepository>(), c.read<SalonRepository>(), c.read<AuthRepository>()),
        child: const _Chat(),
      );
}

/// Opens (or creates) the signed-in customer's conversation with a salon.
Future<void> openSalonChat(BuildContext context, String salonId) async {
  ChatThread? t;
  final ok = await attempt(() async => t = await context.read<EngagementRepository>().openThread(salonId));
  if (ok && t != null && context.mounted) pushPage(context, ChatPage(threadId: t!.id, asSalon: false));
}

class _Chat extends StatefulWidget {
  const _Chat();
  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> _send(ChatViewModel vm) async {
    final t = text.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await attempt(() => vm.send(t));
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      Sfx.soft();
      text.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatViewModel>();
    final c = context.c;
    final top = MediaQuery.paddingOf(context).top;
    final msgs = vm.messages.reversed.toList();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        // header
        Container(
          padding: EdgeInsets.fromLTRB(8, top + 4, 12, 10),
          decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            IconBtn('back', onTap: () {
              Sfx.back();
              Navigator.of(context).maybePop();
            }),
            const SizedBox(width: 6),
            vm.asSalon ? Avatar(vm.title, size: 40, k: vm.palette) : ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 40, height: 40, child: SalonArt(vm.palette, n: 2, radius: 12, name: vm.title))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(vm.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context)),
                if (vm.subtitle.isNotEmpty) Text(vm.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.cap(context)),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: msgs.isEmpty
              ? ListView(children: [
                  EmptyState(
                    icon: 'msg',
                    title: vm.asSalon ? tr('No messages yet') : tr('Ask {salon} anything', {'salon': vm.title}),
                    text: vm.asSalon ? tr('Messages from this customer will appear here.') : tr('Questions about services, prices or timings. The salon replies here and you get a notification.'),
                  ),
                ])
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final m = msgs[i];
                    final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                    final mine = m.fromSalon == vm.asSalon;
                    return Column(children: [
                      if (older == null || !sameDay(older.at, m.at)) _DaySep(m.at),
                      _Bubble(m, mine: mine, tight: older != null && older.fromSalon == m.fromSalon && sameDay(older.at, m.at)),
                    ]);
                  },
                ),
        ),
        // composer
        Container(
          // Above the keyboard: no extra gesture-bar padding; otherwise clear it.
          padding: EdgeInsets.fromLTRB(kGutter, 10, 10, 10 + (keyboard ? 0 : MediaQuery.paddingOf(context).bottom)),
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: text,
                minLines: 1,
                maxLines: 5,
                maxLength: 1000,
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
              opacity: text.text.trim().isEmpty ? .4 : 1,
              child: Tap(
                onTap: text.text.trim().isEmpty ? null : () => _send(vm),
                sound: false,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(gradient: G.btn, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Padding(padding: EdgeInsets.only(left: 2), child: HIcon('nav', size: 20, color: Colors.white)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
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
  const _Bubble(this.m, {required this.mine, required this.tight});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = const Radius.circular(18);
    return Padding(
      padding: EdgeInsets.only(top: tight ? 3 : 10, left: mine ? 48 : 0, right: mine ? 0 : 48),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Reveal(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              gradient: mine ? G.btn : null,
              color: mine ? null : c.surface,
              borderRadius: BorderRadius.only(topLeft: r, topRight: r, bottomLeft: mine ? r : const Radius.circular(6), bottomRight: mine ? const Radius.circular(6) : r),
              boxShadow: mine ? null : c.lift,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Text(m.text, style: T.body(context).copyWith(color: mine ? Colors.white : c.ink, height: 22 / 16)),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(fmtTime(m.at), style: T.cap(context).copyWith(fontSize: 11, color: mine ? Colors.white70 : c.subtle)),
                if (mine) ...[const SizedBox(width: 4), HIcon('check', size: 12, stroke: 2.4, color: m.read ? Colors.white : Colors.white54)],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
