import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/notifications_view_model.dart';
import '../views/notifications_page.dart';

/// Bell with the live unread count; opens the notifications list.
class NotificationBell extends StatelessWidget {
  final bool onBand;
  const NotificationBell({super.key, this.onBand = true});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => UnreadViewModel(c.read<EngagementRepository>()),
        child: Consumer<UnreadViewModel>(
          builder: (context, vm, _) => Semantics(
            label: vm.count == 0 ? tr('Notifications') : tr('{n} unread notifications', {'n': vm.count}),
            button: true,
            child: IconBtn('bell', onBand: onBand, dot: vm.count, onTap: () => pushPage(context, const NotificationsPage())),
          ),
        ),
      );
}
