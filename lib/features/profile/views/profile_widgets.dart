import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../notifications/notifications.dart';
import '../viewmodels/profile_view_models.dart';
import 'account_pages.dart';
import '../../auth/auth.dart' show toggleFingerprint;
import '../../legal/views/legal_page.dart';
import 'permissions_page.dart';
import '../../../core/security/biometrics.dart' show bio, bioIcon;

/// Identity card for Profile / More tabs. Tap to edit.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => AccountViewModel(c.read<AuthRepository>(), c.read<SalonRepository>()),
    child: Consumer<AccountViewModel>(
      builder: (context, vm, _) {
        final a = vm.account;
        if (a == null) return const SizedBox();
        final c = context.c;
        return HCard(
          onTap: () => pushPage(context, const EditProfilePage()),
          child: Row(
            children: [
              Avatar(a.name, size: 56, k: a.name.codeUnits.fold<int>(0, (s, x) => s + x)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.h3(context)),
                    Text(
                      vm.line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.sm(context).copyWith(color: c.muted),
                    ),
                    Text(
                      a.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.cap(context).copyWith(color: c.subtle),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: HIcon('edit', size: 18, color: c.brandText),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Theme, sounds, password and notifications, shared by every role.
class AppSettingsGroup extends StatelessWidget {
  const AppSettingsGroup({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionViewModel>();
    final unread = context.read<EngagementRepository>().unreadNotifications();
    final mode = switch (s.themeMode) {
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
      _ => 'light',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
          child: Text(tr('SETTINGS'), style: T.eyebrow(context)),
        ),
        Group(
          children: [
            MRow(icon: 'bell', title: tr('Notifications'), sub: unread == 0 ? tr('All caught up') : tr('{n} unread', {'n': unread}), onTap: () => pushPage(context, const NotificationsPage())),
            MRow(icon: 'shield', title: tr('Change password'), onTap: () => pushPage(context, const ChangePasswordPage())),
            if (s.bioAvailable && context.read<AuthRepository>().usesServer)
              MRow(
                icon: bioIcon,
                title: bio(tr('Fingerprint sign-in')),
                sub: s.fingerprintOn ? bio(tr('On: open HOLA with your fingerprint')) : tr('Off: sign in with your password'),
                trailing: HSwitch(on: s.fingerprintOn, onChanged: (v) => toggleFingerprint(context, v)),
              ),
            if (s.account?.role == Role.customer)
              MRow(
                icon: 'clock',
                title: tr('Booking reminders'),
                sub: tr('The day before and 2 hours before each visit'),
                trailing: ListenableBuilder(
                  listenable: context.read<EngagementRepository>().changes,
                  builder: (context, _) => HSwitch(
                    on: context.read<EngagementRepository>().remindersOn,
                    onChanged: (v) =>
                        attempt(() => context.read<EngagementRepository>().setReminders(v), success: v ? tr('Booking reminders on') : tr('Booking reminders off'), icon: v ? 'bell' : 'x'),
                  ),
                ),
              ),
            MRow(icon: 'check', title: tr('Permissions'), sub: tr('Notifications, location, photos'), onTap: () => pushPage(context, const PermissionsPage())),
            MRow(
              icon: 'vol',
              title: tr('Sounds and haptics'),
              trailing: HSwitch(on: s.sound, onChanged: (v) => s.sound = v),
            ),
            MRow(icon: 'doc', title: tr('Terms of use'), onTap: () => pushPage(context, const LegalPage.terms())),
            MRow(icon: 'shield', title: tr('Privacy policy'), onTap: () => pushPage(context, const LegalPage.privacy())),
          ],
        ),
        const SizedBox(height: 12),
        // Appearance sits in its own card so the selector never crowds a row.
        HCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: context.c.brandSoft, borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: HIcon('sun', size: 20, color: context.c.brandText),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      tr('Appearance'),
                      style: TextStyle(fontFamily: T.f, fontSize: 16, fontWeight: FontWeight.w500, color: context.c.ink),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Seg(
                opts: [('system', tr('Auto')), ('light', tr('Light')), ('dark', tr('Dark'))],
                value: mode,
                onChanged: (v) => s.setTheme(switch (v) {
                  'system' => ThemeMode.system,
                  'dark' => ThemeMode.dark,
                  _ => ThemeMode.light,
                }),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: context.c.brandSoft, borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: HIcon('msg', size: 20, color: context.c.brandText),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      tr('Language'),
                      style: TextStyle(fontFamily: T.f, fontSize: 16, fontWeight: FontWeight.w500, color: context.c.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Each language is named in itself, so it's findable whichever one is on.
              Seg(opts: const [('en', 'English'), ('ur', 'اردو')], value: s.language, onChanged: s.setLanguage),
            ],
          ),
        ),
      ],
    );
  }
}

class SignOutButton extends StatelessWidget {
  const SignOutButton({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        HButton(
          tr('Sign out'),
          icon: 'logout',
          kind: BtnKind.dangerSoft,
          block: true,
          onTap: () async {
            final ok = await confirmSheet(
              context,
              title: tr('Sign out?'),
              body: tr('You can sign back in any time with your email and password.'),
              confirm: tr('Sign out'),
              danger: true,
              cancel: tr('Stay signed in'),
            );
            if (!ok || !context.mounted) return;
            final s = context.read<SessionViewModel>();
            Navigator.of(context).popUntil((r) => r.isFirst);
            await s.signOut();
            Sfx.back();
            Fx.toast(tr('Signed out'), icon: 'logout', tone: 'info');
          },
        ),
        const SizedBox(height: 12),
        Text(
          'HOLA Professional 1.0.0',
          textAlign: TextAlign.center,
          style: T.cap(context).copyWith(color: c.subtle),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
