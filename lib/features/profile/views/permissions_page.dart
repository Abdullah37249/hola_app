import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/permissions.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/ui.dart';

/// What each permission is for, by role. Only permissions the role really
/// uses are asked for.
List<(AppPermission, String, String, String)> permissionsFor(Role? role) => [
  (
    AppPermission.notifications,
    'bell',
    'Notifications',
    switch (role) {
      Role.customer => 'Booking confirmations and reminders on your phone.',
      Role.rider => 'New deliveries assigned to you.',
      Role.salesOfficer => 'New salons, orders and training enrolments.',
      _ => 'New bookings, orders and training from HOLA.',
    },
  ),
  if (role == Role.salesOfficer) (AppPermission.location, 'pin', 'Location', 'Records where you are when you check in at a salon.'),
  if (role == Role.rider) (AppPermission.location, 'pin', 'Location', 'Records where you hand over each delivery.'),
  if (role == Role.salonOwner) (AppPermission.photos, 'camera', 'Photos & storage', 'Add pictures of your salon from your gallery.'),
];

/// Lets the person allow (or review) the phone permissions HOLA uses.
/// [firstRun] is the one-time screen after signing in.
class PermissionsPage extends StatefulWidget {
  final bool firstRun;
  const PermissionsPage({super.key, this.firstRun = false});
  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> with WidgetsBindingObserver {
  final Map<AppPermission, PermState> _state = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from system settings: show the new answers.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    for (final p in AppPermission.values) {
      final s = await Permissions.status(p);
      if (!mounted) return;
      setState(() => _state[p] = s);
    }
  }

  Future<void> _ask(AppPermission p) async {
    final s = await Permissions.request(p);
    if (!mounted) return;
    setState(() => _state[p] = s);
    if (s == PermState.granted) Fx.toast(tr('Allowed'), icon: 'check');
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<SessionViewModel>().account?.role;
    final list = permissionsFor(role);
    final c = context.c;
    return HPage(
      title: widget.firstRun ? tr('Allow access') : tr('Permissions'),
      footer: widget.firstRun ? FootBar(child: HButton(tr('Continue'), block: true, onTap: () => Navigator.of(context).maybePop())) : null,
      children: [
        const SizedBox(height: 8),
        Text(
          widget.firstRun ? tr('HOLA works best with these. You can change them any time in Settings.') : tr('What HOLA can use on this phone, and why.'),
          style: T.sm(context).copyWith(color: c.muted),
        ),
        const SizedBox(height: 18),
        for (final (p, icon, title, why) in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HCard(
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      gradient: G.btn,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x992F80FF), blurRadius: 18, spreadRadius: -6)],
                    ),
                    alignment: Alignment.center,
                    child: HIcon(icon, size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(title), style: T.ttl(context)),
                        Text(tr(why), style: T.cap(context)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  switch (_state[p]) {
                    PermState.granted => ToneBadge(tr('Allowed'), tone: 'ok'),
                    PermState.blocked => HButton(tr('Settings'), small: true, kind: BtnKind.secondary, onTap: Permissions.openSettings),
                    PermState.denied => HButton(tr('Allow'), small: true, onTap: () => _ask(p)),
                    null => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  },
                ],
              ),
            ),
          ),
        if (list.any((x) => _state[x.$1] == PermState.blocked)) Text(tr('Turned off for good? Tap Settings, then Permissions, to allow it.'), style: T.cap(context)),
      ],
    );
  }
}
