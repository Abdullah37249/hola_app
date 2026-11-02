import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/sfx.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/logo.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/auth_view_models.dart';
import '../widgets/auth_widgets.dart';
import 'forgot_password_view.dart';
import 'sign_up_view.dart';

/// First screen for anyone signed out: sign in, or create an account.
/// The account's role decides which experience opens afterwards.
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => SignInViewModel(c.read<AuthRepository>()), child: const _SignIn());
}

class _SignIn extends StatefulWidget {
  const _SignIn();
  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final email = TextEditingController(), pass = TextEditingController();
  final errors = FieldErrors();

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    errors.dispose();
    super.dispose();
  }

  Future<void> _submit(SignInViewModel vm) async {
    FocusScope.of(context).unfocus();
    String? name;
    final ok = await attempt(() async => name = (await vm.signIn(email.text, pass.text)).firstName, errors: errors);
    if (ok) TextInput.finishAutofillContext(); // offer to save the password
    if (ok) {
      Sfx.success();
      Fx.toast(tr('Welcome back, {name}', {'name': name}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SignInViewModel>();
    final c = context.c;
    return AuthScaffold(
      children: [
        AuthHeading(top: Logo(height: 36, white: true), title: tr('Welcome back'), sub: tr('Salons, bookings and HOLA professional, in one place.')),
        const SizedBox(height: 28),
        AutofillGroup(
          child: AuthCard(
            children: [
              Text(tr('Sign in'), style: T.h2(context)),
              HField(
                label: tr('Email'),
                icon: 'mail',
                hint: tr('you@example.com'),
                controller: email,
                keyboard: TextInputType.emailAddress,
                autofill: const [AutofillHints.email, AutofillHints.username],
                name: 'email',
                errors: errors,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PasswordField(controller: pass, obscure: vm.obscure, onToggle: vm.toggleObscure, action: TextInputAction.done, onSubmitted: (_) => _submit(vm), errors: errors),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Sfx.tap();
                        pushPage(context, ForgotPasswordView(email: email.text.trim()));
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 0, 4),
                        child: Text(tr('Forgot password?'), style: T.link(context)),
                      ),
                    ),
                  ),
                ],
              ),
              HButton(tr('Sign in'), block: true, onTap: () => _submit(vm)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Divider(color: c.line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(tr('New to HOLA?'), style: T.sub(context)),
            ),
            Expanded(child: Divider(color: c.line)),
          ],
        ),
        const SizedBox(height: 16),
        HButton(tr('Create an account'), icon: 'sparkle', kind: BtnKind.secondary, block: true, onTap: () => pushPage(context, const SignUpView())),
        const SizedBox(height: 12),
        Text(tr('For customers, salon owners and the HOLA team.\nSalon staff sign in with the details their owner set up.'), textAlign: TextAlign.center, style: T.cap(context)),
      ],
    );
  }
}
