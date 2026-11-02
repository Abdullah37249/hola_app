import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/chat_view_models.dart';
import 'chat_page.dart';

/// Salon side: conversations customers started with this salon.
class ChatInboxPage extends StatelessWidget {
  const ChatInboxPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => ChatInboxViewModel(c.read<EngagementRepository>(), c.read<AuthRepository>()),
        child: Consumer<ChatInboxViewModel>(
          builder: (context, vm, _) => _Inbox(
            title: tr('Messages'),
            sub: tr('Questions customers sent your salon'),
            threads: vm.threads,
            asSalon: true,
            empty: EmptyState(icon: 'msg', title: tr('No messages yet'), text: tr('When a customer messages your salon from its HOLA page, the conversation appears here.')),
          ),
        ),
      );
}

/// Customer side: conversations with salons.
class CustomerChatsPage extends StatelessWidget {
  const CustomerChatsPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => CustomerChatsViewModel(c.read<EngagementRepository>(), c.read<SalonRepository>(), c.read<AuthRepository>()),
        child: Consumer<CustomerChatsViewModel>(
          builder: (context, vm, _) => _Inbox(
            title: tr('Messages'),
            sub: tr('Your conversations with salons'),
            threads: vm.threads,
            asSalon: false,
            empty: EmptyState(icon: 'msg', title: tr('No conversations yet'), text: tr('Open a salon and tap Message to ask about services, prices or timings.')),
          ),
        ),
      );
}

class _Inbox extends StatelessWidget {
  final String title, sub;
  final List<ThreadSummary> threads;
  final bool asSalon;
  final Widget empty;
  const _Inbox({required this.title, required this.sub, required this.threads, required this.asSalon, required this.empty});
  @override
  Widget build(BuildContext context) {
    final unread = threads.fold(0, (s, t) => s + t.unread);
    return HPage(
      title: title,
      alwaysTitle: false,
      children: [
        Reveal(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.h1(context)),
            Text(unread == 0 ? sub : plural(unread, 'unread message'), style: T.sm(context).copyWith(color: context.c.muted)),
          ]),
        ),
        const SizedBox(height: 16),
        if (threads.isEmpty)
          empty
        else
          HCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < threads.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 72, color: context.c.line),
                Reveal(i: i, child: _ThreadRow(threads[i], asSalon: asSalon)),
              ],
            ]),
          ),
      ],
    );
  }
}

class _ThreadRow extends StatelessWidget {
  final ThreadSummary t;
  final bool asSalon;
  const _ThreadRow(this.t, {required this.asSalon});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final last = t.last;
    final preview = last == null ? '' : '${last.fromSalon == asSalon ? 'You: ' : ''}${last.text}';
    return InkWell(
      onTap: () {
        Sfx.tap();
        pushPage(context, ChatPage(threadId: t.thread.id, asSalon: asSalon));
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          asSalon ? Avatar(t.name, size: 46, k: t.palette) : ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 46, height: 46, child: SalonArt(t.palette, n: 2, radius: 14, name: t.name))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.ttl(context).copyWith(fontWeight: t.unread > 0 ? FontWeight.w700 : FontWeight.w600))),
                if (last != null) Text(sameDay(last.at, now()) ? fmtTime(last.at) : dayLabel(last.at, today), style: T.cap(context).copyWith(color: t.unread > 0 ? c.brandText : c.subtle)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sm(context).copyWith(color: t.unread > 0 ? c.ink : c.muted))),
                if (t.unread > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(gradient: G.btn, borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: Text('${t.unread}', style: const TextStyle(fontFamily: T.f, color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1)),
                  ),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
