import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/chat_view_models.dart';
import 'chat_page.dart';

/// The signed-in person's conversations: a customer's with salons, a salon's
/// with clients and riders, a rider's with salons.
class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => InboxViewModel(c.read<ChatRepository>(), c.read<SalonRepository>()),
    child: Consumer<InboxViewModel>(builder: (context, vm, _) => _Inbox(vm)),
  );
}

class _Inbox extends StatelessWidget {
  final InboxViewModel vm;
  const _Inbox(this.vm);
  @override
  Widget build(BuildContext context) {
    final threads = vm.threads;
    final unread = vm.unread;
    final side = vm.chat.mySide;
    final sub = switch (side) {
      ChatSide.salon => tr('Your clients and delivery riders'),
      ChatSide.rider => tr('Salons you deliver to'),
      _ => tr('Your conversations with salons'),
    };
    return HPage(
      title: tr('Messages'),
      alwaysTitle: false,
      onRefresh: vm.chat.live ? vm.pull : null,
      children: [
        Reveal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Messages'), style: T.h1(context)),
              Text(unread == 0 ? sub : plural(unread, 'unread message'), style: T.sm(context).copyWith(color: context.c.muted)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (vm.isSalon && vm.hasRiders) ...[
          Wrap(
            spacing: 8,
            children: [
              for (final (id, label) in [('all', tr('All')), ('clients', tr('Clients')), ('riders', tr('Riders'))])
                ChoiceChip(label: Text(label), selected: vm.filter == id, onSelected: (_) => vm.setFilter(id)),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (threads.isEmpty)
          EmptyState(
            icon: 'msg',
            title: tr('No conversations yet'),
            text: switch (side) {
              ChatSide.salon => tr('Message a client from their booking, or a rider from a dispatched order. Clients can also write to you from your HOLA page.'),
              ChatSide.rider => tr('Open a delivery and tap Message salon to talk about that order.'),
              _ => tr('Open a salon or one of your bookings and tap Message to ask about services, prices or timings.'),
            },
          )
        else
          HCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < threads.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 72, color: context.c.line),
                  Reveal(
                    i: i < 10 ? i : 10,
                    child: _ThreadRow(threads[i], mySide: side),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ThreadRow extends StatelessWidget {
  final ThreadSummary t;
  final String mySide;
  const _ThreadRow(this.t, {required this.mySide});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final last = t.last;
    final body = last == null
        ? ''
        : last.text.isNotEmpty
        ? last.text
        : last.ref != null
        ? '${tr(last.ref!.title)} ${last.ref!.code}'.trim()
        : '📷 ${tr('Photo')}';
    final preview = last == null ? t.about : '${last.side == mySide ? tr('You: ') : ''}$body';
    return InkWell(
      onTap: () {
        Sfx.tap();
        pushPage(context, ChatPage(threadId: t.thread.id));
      },
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            t.salonSide
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(width: 46, height: 46, child: SalonArt(t.palette, n: 2, radius: 14, name: t.name)),
                  )
                : Avatar(t.name, size: 46, k: t.palette),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.ttl(context).copyWith(fontWeight: t.unread > 0 ? FontWeight.w700 : FontWeight.w600),
                              ),
                            ),
                            if (t.tag.isNotEmpty) ...[const SizedBox(width: 6), ToneBadge(t.tag, tone: 'info')],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (last != null) Text(sameDay(last.at, now()) ? fmtTime(last.at) : dayLabel(last.at, today), style: T.cap(context).copyWith(color: t.unread > 0 ? c.brandText : c.subtle)),
                    ],
                  ),
                  if (t.about.isNotEmpty && last != null)
                    Text(
                      t.about,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.cap(context).copyWith(color: c.brandText, fontWeight: FontWeight.w600),
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.sm(context).copyWith(color: t.unread > 0 ? c.ink : c.muted),
                        ),
                      ),
                      if (t.unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(gradient: G.btn, borderRadius: BorderRadius.circular(10)),
                          alignment: Alignment.center,
                          child: Text(
                            '${t.unread}',
                            style: const TextStyle(fontFamily: T.f, color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
