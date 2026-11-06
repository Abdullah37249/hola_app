import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../../auth/viewmodels/auth_view_models.dart' show strengthHint;
import '../../auth/widgets/auth_widgets.dart' show PasswordField, StrengthMeter;
import '../viewmodels/profile_view_models.dart';

/// Where people ask HOLA to close an account the app can't delete itself.
const kDeletionEmail = 'info@metaxperts.net';

/// Opens an email to HOLA asking to delete the account signed in as [email].
Future<void> requestAccountDeletion(String email) async {
  final uri = Uri(
    scheme: 'mailto',
    path: kDeletionEmail,
    query: 'subject=${Uri.encodeComponent('HOLA account deletion request')}&body=${Uri.encodeComponent('Please delete my HOLA account and its data.\nAccount email: $email')}',
  );
  try {
    if (await launchUrl(uri)) return;
  } catch (_) {}
  Fx.toast(tr('No email app found. Write to {email}', {'email': kDeletionEmail}), icon: 'alert', tone: 'bad');
}

class EditProfilePage extends StatelessWidget {
  const EditProfilePage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => EditProfileViewModel(c.read<AuthRepository>()), child: const _EditProfile());
}

class _EditProfile extends StatefulWidget {
  const _EditProfile();
  @override
  State<_EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<_EditProfile> {
  late final vm = context.read<EditProfileViewModel>();
  late final name = TextEditingController(text: vm.account.name), phone = TextEditingController(text: vm.account.phone), city = TextEditingController(text: vm.account.city);
  final errors = FieldErrors();

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    city.dispose();
    errors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = vm.account;
    return HPage(
      title: tr('Edit profile'),
      footer: HButton(
        tr('Save changes'),
        block: true,
        onTap: () async {
          FocusScope.of(context).unfocus();
          final nav = Navigator.of(context);
          if (await attempt(
            () => vm.save(name: name.text, phone: phone.text, city: city.text),
            success: tr('Profile updated'),
            errors: errors,
          )) {
            nav.pop();
          }
        },
      ),
      children: staggered([
        Center(child: Avatar(a.name, size: 84, k: a.name.codeUnits.fold<int>(0, (s, x) => s + x))),
        const SizedBox(height: 10),
        Center(child: ToneBadge(a.role.label, tone: 'info')),
        const SizedBox(height: 24),
        VStack(gap: 14, [
          HField(label: tr('Full name'), icon: 'user', controller: name, caps: TextCapitalization.words, autofill: const [AutofillHints.name], name: 'name', errors: errors),
          // Read-only: shown as text so it never looks editable.
          HCard(
            color: context.c.surface2,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                HIcon('msg', size: 20, color: context.c.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Email'), style: T.cap(context)),
                      Text(
                        a.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.sm(context).copyWith(color: context.c.ink, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Text(tr('Sign-in'), style: T.cap(context)),
              ],
            ),
          ),
          HField(label: tr('Phone'), icon: 'phone', controller: phone, keyboard: TextInputType.phone, autofill: const [AutofillHints.telephoneNumber], name: 'phone', errors: errors),
          HField(
            label: tr('City'),
            icon: 'pin',
            controller: city,
            caps: TextCapitalization.words,
            autofill: const [AutofillHints.addressCity],
            action: TextInputAction.done,
            name: 'city',
            errors: errors,
          ),
        ]),
        if (a.role == Role.customer) ...[
          const SizedBox(height: 28),
          Group(
            children: [
              MRow(icon: 'alert', title: tr('Delete account'), sub: tr('Remove your profile and sign out'), titleColor: context.c.badInk, onTap: () => pushPage(context, const DeleteAccountPage())),
            ],
          ),
        ] else ...[
          // Accounts HOLA manages are closed by HOLA: the person asks by email.
          const SizedBox(height: 28),
          Group(
            children: [
              MRow(icon: 'alert', title: tr('Request account deletion'), sub: tr('Email HOLA to close your account'), titleColor: context.c.badInk, onTap: () => requestAccountDeletion(a.email)),
            ],
          ),
        ],
      ]),
    );
  }
}

class ChangePasswordPage extends StatelessWidget {
  const ChangePasswordPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => ChangePasswordViewModel(c.read<AuthRepository>()), child: const _ChangePassword());
}

class _ChangePassword extends StatefulWidget {
  const _ChangePassword();
  @override
  State<_ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<_ChangePassword> {
  final current = TextEditingController(), confirm = TextEditingController();
  final errors = FieldErrors();
  bool _hideCurrent = true;

  @override
  void dispose() {
    current.dispose();
    confirm.dispose();
    errors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChangePasswordViewModel>();
    return HPage(
      title: tr('Change password'),
      alwaysTitle: false,
      footer: HButton(
        tr('Update password'),
        block: true,
        onTap: () async {
          FocusScope.of(context).unfocus();
          final nav = Navigator.of(context);
          if (await attempt(() => vm.change(current.text, confirm.text), success: tr('Password updated'), icon: 'shield', errors: errors)) nav.pop();
        },
      ),
      children: staggered([
        Text(tr('Change password'), style: T.h1(context)),
        const SizedBox(height: 4),
        Text(tr('Use at least 8 characters. A mix of letters, numbers and symbols is strongest.'), style: T.body(context).copyWith(color: context.c.muted)),
        const SizedBox(height: 20),
        VStack(gap: 14, [
          PasswordField(label: tr('Current password'), controller: current, obscure: _hideCurrent, onToggle: () => setState(() => _hideCurrent = !_hideCurrent), name: 'current', errors: errors),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasswordField(label: tr('New password'), obscure: vm.obscure, onToggle: vm.toggleObscure, onChanged: vm.setNext, autofill: AutofillHints.newPassword, errors: errors),
              const SizedBox(height: 8),
              StrengthMeter(strength: vm.strength, hint: strengthHint(vm.strength)),
            ],
          ),
          PasswordField(
            label: tr('Confirm new password'),
            controller: confirm,
            obscure: vm.obscure,
            onToggle: vm.toggleObscure,
            action: TextInputAction.done,
            autofill: AutofillHints.newPassword,
            name: 'confirm',
            errors: errors,
          ),
        ]),
      ]),
    );
  }
}

class DeleteAccountPage extends StatelessWidget {
  const DeleteAccountPage({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => DeleteAccountViewModel(c.read<AuthRepository>()), child: const _DeleteAccount());
}

class _DeleteAccount extends StatefulWidget {
  const _DeleteAccount();
  @override
  State<_DeleteAccount> createState() => _DeleteAccountState();
}

class _DeleteAccountState extends State<_DeleteAccount> {
  final pass = TextEditingController();
  final errors = FieldErrors();
  bool _hide = true;

  @override
  void dispose() {
    pass.dispose();
    errors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<DeleteAccountViewModel>();
    final c = context.c;
    return HPage(
      title: tr('Delete account'),
      alwaysTitle: false,
      footer: HButton(
        tr('Delete my account'),
        block: true,
        kind: BtnKind.danger,
        onTap: () async {
          FocusScope.of(context).unfocus();
          final ok = await confirmSheet(context, title: tr('Delete your account?'), body: tr("This can't be undone."), confirm: tr('Delete permanently'), danger: true, cancel: tr('Keep my account'));
          if (!ok || !context.mounted) return;
          final nav = Navigator.of(context);
          if (await attempt(() => vm.delete(pass.text), success: tr('Your account was deleted'), icon: 'check', errors: errors)) nav.popUntil((r) => r.isFirst);
        },
      ),
      children: staggered([
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: c.badSoft, borderRadius: BorderRadius.circular(20)),
          alignment: Alignment.center,
          child: HIcon('alert', size: 30, color: c.badInk),
        ),
        const SizedBox(height: 16),
        Text(tr('Delete your account'), style: T.h1(context)),
        const SizedBox(height: 8),
        Text(
          tr('Your profile, favourites and notifications are removed and you are signed out. Salons keep the name on past bookings for their records.'),
          style: T.body(context).copyWith(color: c.muted),
        ),
        const SizedBox(height: 20),
        PasswordField(label: tr('Confirm with your password'), controller: pass, obscure: _hide, onToggle: () => setState(() => _hide = !_hide), action: TextInputAction.done, errors: errors),
      ]),
    );
  }
}
