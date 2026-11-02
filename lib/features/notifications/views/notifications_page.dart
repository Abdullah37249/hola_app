import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/links.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/notifications_view_model.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => NotificationsViewModel(c.read<EngagementRepository>()), child: const _Notifications());
}

/// Icons notifications may carry; anything else falls back to the bell.
const _known = {'bell', 'cal', 'check', 'x', 'star', 'msg', 'alert', 'store', 'box', 'truck', 'cash', 'grad', 'users', 'sparkle'};
String _icon(String i) => i == 'spark' ? 'sparkle' : (_known.contains(i) ? i : 'bell');

class _Notifications extends StatelessWidget {
  const _Notifications();
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationsViewModel>();
    return HPage(
      title: tr('Notifications'),
      alwaysTitle: false,
      trailing: vm.unread == 0
          ? null
          : IconBtn('check', raised: true, onTap: () => attempt(vm.markAllRead, success: tr('All marked as read'), icon: 'check')),
      children: [
        Reveal(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Notifications'), style: T.h1(context)),
            Text(vm.unread == 0 ? tr("You're all caught up") : plural(vm.unread, 'unread update'), style: T.sm(context).copyWith(color: context.c.muted)),
          ]),
        ),
        const SizedBox(height: 20),
        if (vm.all.isEmpty)
          EmptyState(icon: 'bell', title: tr('No notifications yet'), text: tr('Booking updates, messages, orders and reminders will appear here as they happen.'))
        else ...[
          if (vm.todays.isNotEmpty) _Section(tr('Today'), vm.todays, vm),
          if (vm.earlier.isNotEmpty) _Section(tr('Earlier'), vm.earlier, vm),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<AppNotification> items;
  final NotificationsViewModel vm;
  const _Section(this.title, this.items, this.vm);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(4, 0, 0, 8), child: Text(title.toUpperCase(), style: T.eyebrow(context))),
          HCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 64, color: context.c.line),
                Reveal(i: i, child: _Row(items[i], vm)),
              ],
            ]),
          ),
        ]),
      );
}

class _Row extends StatelessWidget {
  final AppNotification n;
  final NotificationsViewModel vm;
  const _Row(this.n, this.vm);
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: () {
        Sfx.tap();
        vm.open(n);
        if (n.link != null) openLink(context, n.link!);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: n.read ? c.bg2 : c.brandSoft, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: HIcon(_icon(n.icon), size: 19, color: n.read ? c.muted : c.brandText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(tr(n.title, n.args), style: T.ttl(context).copyWith(fontWeight: n.read ? FontWeight.w500 : FontWeight.w600, color: n.read ? c.body : c.ink))),
                const SizedBox(width: 8),
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(ago(n.at, now()), style: T.cap(context).copyWith(color: c.subtle))),
              ]),
              const SizedBox(height: 2),
              Text(tr(n.body, n.args), maxLines: 3, overflow: TextOverflow.ellipsis, style: T.sm(context).copyWith(color: c.muted)),
            ]),
          ),
          if (!n.read) ...[
            const SizedBox(width: 8),
            Container(margin: const EdgeInsets.only(top: 6), width: 9, height: 9, decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle)),
          ],
        ]),
      ),
    );
  }
}
