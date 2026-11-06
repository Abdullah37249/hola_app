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
import '../../../app/viewmodels/session_view_model.dart';
import 'fingerprint_views.dart';
import 'forgot_password_view.dart';
import 'sign_up_view.dart';

/// First screen for anyone signed out: sign in, or create an account.
/// The account's role decides which experience opens afterwards.
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => SignInViewModel(c.read<AuthRepository>()), child: const _SignIn());
}

/// Sign-in for HOLA delivery riders, with the account HOLA created for them.
/// (Riders don't sign up in the app; HOLA registers them on its server.)
class RiderSignInView extends StatelessWidget {
  const RiderSignInView({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => SignInViewModel(c.read<AuthRepository>()), child: const _SignIn(rider: true));
}

class _SignIn extends StatefulWidget {
  const _SignIn({this.rider = false});
  final bool rider;
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
    final nav = Navigator.of(context);
    final session = context.read<SessionViewModel>();
    final ok = await attempt(() async => name = (await vm.signIn(email.text, pass.text)).firstName, errors: errors);
    if (ok) TextInput.finishAutofillContext(); // offer to save the password
    if (ok && widget.rider) nav.popUntil((r) => r.isFirst);
    if (ok) {
      Sfx.success();
      Fx.toast(tr('Welcome back, {name}', {'name': name}));
      session.passwordSignedIn(); // first time: offer fingerprint sign-in
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SignInViewModel>();
    final c = context.c;
    return AuthScaffold(
      back: widget.rider,
      children: [
        if (widget.rider)
          AuthHeading(eyebrow: tr('HOLA delivery'), title: tr('Rider sign in'), sub: tr('Use the email and password HOLA gave you. Your assigned orders open straight away.'))
        else
          AuthHeading(
            top: const Center(child: Logo(height: 54, white: true)),
            title: tr('Welcome back'),
            sub: tr('Salons, bookings and HOLA professional, in one place.'),
          ),
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
              // Fingerprint sign-in saved on this phone: its icon sits beside Sign in.
              // The fingerprint icon is always there; before any account has
              // turned fingerprint sign-in on, it explains how to.
              Row(
                children: [
                  Expanded(child: HButton(tr('Sign in'), block: true, onTap: () => _submit(vm))),
                  const SizedBox(width: 10),
                  FingerprintSignInButton(riders: widget.rider, onSignedIn: widget.rider ? () => Navigator.of(context).popUntil((r) => r.isFirst) : null),
                ],
              ),
            ],
          ),
        ),
        if (!widget.rider) ...[
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
          Text(tr('Sign up as a customer or a salon. HOLA officers and riders sign in with the account HOLA gave them.'), textAlign: TextAlign.center, style: T.cap(context)),
          const SizedBox(height: 20),
          // HOLA's delivery riders have their own way in.
          HCard(
            onTap: () => pushPage(context, const RiderSignInView()),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: HIcon('truck', size: 22, color: c.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Delivery rider?'), style: T.ttl(context)),
                      Text(tr('Sign in to see the orders assigned to you'), style: T.cap(context)),
                    ],
                  ),
                ),
                HIcon('chev', size: 18, color: c.muted),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
