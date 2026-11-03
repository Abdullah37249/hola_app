import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/auth_view_models.dart';
import '../widgets/auth_widgets.dart';

/// Reset a forgotten password by proving the phone number on the account.
class ForgotPasswordView extends StatelessWidget {
  final String email;
  const ForgotPasswordView({super.key, this.email = ''});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => ResetPasswordViewModel(c.read<AuthRepository>()),
    child: _Reset(email: email),
  );
}

class _Reset extends StatefulWidget {
  final String email;
  const _Reset({required this.email});
  @override
  State<_Reset> createState() => _ResetState();
}

class _ResetState extends State<_Reset> {
  late final email = TextEditingController(text: widget.email);
  final phone = TextEditingController();
  final errors = FieldErrors();

  @override
  void dispose() {
    email.dispose();
    phone.dispose();
    errors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ResetPasswordViewModel>();
    // HOLA accounts: the server emails a reset link.
    if (context.read<AuthRepository>().usesServer) {
      return AuthScaffold(
        back: true,
        bandHeight: 330,
        title: tr('Reset password'),
        children: [
          AuthHeading(title: tr('Reset password'), sub: tr('Enter the email on your account and HOLA will email you a link to choose a new password.')),
          const SizedBox(height: 22),
          AuthCard(
            children: [
              HField(
                label: tr('Email'),
                icon: 'mail',
                hint: tr('you@example.com'),
                controller: email,
                keyboard: TextInputType.emailAddress,
                autofill: const [AutofillHints.email],
                action: TextInputAction.done,
                name: 'email',
                errors: errors,
              ),
              HButton(
                tr('Send reset link'),
                icon: 'mail',
                block: true,
                onTap: () async {
                  FocusScope.of(context).unfocus();
                  final nav = Navigator.of(context);
                  final ok = await attempt(
                    () => context.read<AuthRepository>().requestPasswordReset(email.text),
                    success: tr('If an account exists for that email, HOLA has sent a reset link.'),
                    icon: 'mail',
                    errors: errors,
                  );
                  if (ok) nav.pop();
                },
              ),
            ],
          ),
        ],
      );
    }
    return AuthScaffold(
      back: true,
      bandHeight: 330,
      title: tr('Reset password'),
      children: [
        AuthHeading(title: tr('Reset password'), sub: tr('Confirm the email and phone number on your account, then choose a new password.')),
        const SizedBox(height: 22),
        AuthCard(
          children: [
            HField(
              label: tr('Email'),
              icon: 'mail',
              hint: tr('you@example.com'),
              controller: email,
              keyboard: TextInputType.emailAddress,
              autofill: const [AutofillHints.email],
              name: 'email',
              errors: errors,
            ),
            HField(
              label: tr('Phone on the account'),
              icon: 'phone',
              hint: '03xx xxxxxxx',
              controller: phone,
              keyboard: TextInputType.phone,
              autofill: const [AutofillHints.telephoneNumber],
              name: 'phone',
              errors: errors,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PasswordField(
                  label: tr('New password'),
                  hint: tr('At least 8 characters'),
                  obscure: vm.obscure,
                  onToggle: vm.toggleObscure,
                  onChanged: vm.setPassword,
                  action: TextInputAction.done,
                  autofill: AutofillHints.newPassword,
                  errors: errors,
                ),
                const SizedBox(height: 8),
                StrengthMeter(strength: vm.strength, hint: strengthHint(vm.strength)),
              ],
            ),
            HButton(
              tr('Reset password'),
              block: true,

              onTap: () async {
                FocusScope.of(context).unfocus();
                final nav = Navigator.of(context);
                final ok = await attempt(
                  () => vm.reset(email: email.text, phone: phone.text),
                  success: tr('Password changed. Sign in with your new password.'),
                  errors: errors,
                );
                if (ok) nav.pop();
              },
            ),
          ],
        ),
      ],
    );
  }
}
