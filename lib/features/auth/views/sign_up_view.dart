import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/gps_capture.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/auth_view_models.dart';
import '../../legal/views/legal_page.dart';
import '../widgets/auth_widgets.dart';

/// Create an account: choose a role, then personal details.
class SignUpView extends StatelessWidget {
  const SignUpView({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(create: (c) => SignUpViewModel(c.read<AuthRepository>()), child: const _SignUp());
}

Map<Role, (String, String)> get _roleInfo => {
  Role.customer: ('user', tr('Book appointments at salons near you, keep favourites and review your visits.')),
  Role.salonOwner: ('store', tr('List your salon, manage bookings, your team, menu and HOLA trade orders.')),
};

class _SignUp extends StatefulWidget {
  const _SignUp();
  @override
  State<_SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<_SignUp> {
  final name = TextEditingController(), email = TextEditingController(), phone = TextEditingController(), city = TextEditingController();
  final salonName = TextEditingController(), address = TextEditingController(), area = TextEditingController();
  final errors = FieldErrors();
  int step = 0;
  GeoFix? gps; // the salon's door, captured with its address

  @override
  void dispose() {
    for (final c in [name, email, phone, city, salonName, address, area]) {
      c.dispose();
    }
    errors.dispose();
    super.dispose();
  }

  Future<void> _submit(SignUpViewModel vm) async {
    FocusScope.of(context).unfocus();
    final nav = Navigator.of(context);
    final ok = await attempt(
      () => vm.submit(
        name: name.text,
        email: email.text,
        phone: phone.text,
        city: city.text,
        salon: vm.role == Role.salonOwner ? SalonDraft(name: salonName.text, address: address.text, area: area.text, location: gps) : null,
      ),
      errors: errors,
    );
    if (!ok) return;
    TextInput.finishAutofillContext();
    nav.popUntil((r) => r.isFirst);
    Sfx.success();
    Fx.confetti();
    Fx.toast(tr('Welcome to HOLA, {name}', {'name': name.text.trim().split(' ').first}));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SignUpViewModel>();
    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (did, _) {
        if (!did) setState(() => step = 0);
      },
      child: AuthScaffold(
        back: true,
        bandHeight: 330,
        title: step == 0 ? tr('Create account') : tr('Your details'),
        children: [
          AuthHeading(
            eyebrow: 'Step ${step + 1} of 2',
            title: step == 0 ? tr('Create your account') : tr('Your details'),
            sub: step == 0 ? tr('How will you use HOLA?') : tr('Signing up as {role}.', {'role': vm.role!.label.toLowerCase()}),
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(.06, 0), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: step == 0 ? _roles(context, vm) : _details(context, vm),
          ),
        ],
      ),
    );
  }

  Widget _roles(BuildContext context, SignUpViewModel vm) => Column(
    key: const ValueKey('roles'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final r in Role.signUp) ...[
        _RoleTile(
          role: r,
          on: vm.role == r,
          onTap: () {
            Sfx.toggle();
            vm.pickRole(r);
          },
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 8),
      HButton(
        vm.role == null ? tr("Choose how you'll use HOLA") : tr('Continue as {role}', {'role': vm.role!.label.toLowerCase()}),
        block: true,
        onTap: vm.role == null ? null : () => setState(() => step = 1),
      ),
    ],
  );

  Widget _details(BuildContext context, SignUpViewModel vm) => AutofillGroup(
    key: const ValueKey('details'),
    child: AuthCard(
      children: [
        HField(
          label: tr('Full name'),
          icon: 'user',
          hint: tr('e.g. Mariam Siddiqui'),
          controller: name,
          caps: TextCapitalization.words,
          autofill: const [AutofillHints.name],
          name: 'name',
          errors: errors,
        ),
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
          label: tr('Phone'),
          icon: 'phone',
          hint: '03xx xxxxxxx',
          controller: phone,
          keyboard: TextInputType.phone,
          autofill: const [AutofillHints.telephoneNumber],
          helper: tr('Used to recover your account if you forget the password.'),
          name: 'phone',
          errors: errors,
        ),
        // A salon goes live on HOLA straight away, so it needs its name and address now.
        if (vm.role == Role.salonOwner) ...[
          HField(label: tr('Salon name'), icon: 'store', hint: tr('e.g. Maison Noor'), controller: salonName, caps: TextCapitalization.words, name: 'salonName', errors: errors),
          HField(
            label: tr('Street address'),
            icon: 'pin',
            hint: tr('e.g. 12-B Main Boulevard'),
            controller: address,
            caps: TextCapitalization.words,
            autofill: const [AutofillHints.streetAddressLine1],
            name: 'address',
            errors: errors,
          ),
          HField(label: tr('Area'), icon: 'pin', hint: tr('e.g. Gulberg III'), controller: area, caps: TextCapitalization.words, name: 'area', errors: errors),
        ],
        HField(label: tr('City'), icon: 'pin', hint: tr('e.g. Lahore'), controller: city, caps: TextCapitalization.words, autofill: const [AutofillHints.addressCity], name: 'city', errors: errors),
        if (vm.role == Role.salonOwner) GpsCapture(value: gps, onChanged: (v) => setState(() => gps = v)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
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
        // The whole row toggles the box; a comfortable 48 dp target.
        Tap(
          onTap: () {
            Sfx.toggle();
            vm.toggleTerms();
          },
          sound: false,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(
              color: vm.terms ? context.c.brandSoft : context.c.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: vm.terms ? context.c.brandLine : context.c.line),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: vm.terms ? context.c.brand : context.c.surface,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: vm.terms ? context.c.brand : context.c.subtle, width: 1.6),
                  ),
                  alignment: Alignment.center,
                  child: vm.terms ? const HIcon('check', size: 14, stroke: 3, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: const _TermsText()),
              ],
            ),
          ),
        ),
        HButton(tr('Create account'), block: true, onTap: () => _submit(vm)),
        HButton(tr('Change account type'), block: true, kind: BtnKind.ghost, small: true, onTap: () => setState(() => step = 0)),
      ],
    ),
  );
}

class _RoleTile extends StatelessWidget {
  final Role role;
  final bool on;
  final VoidCallback onTap;
  const _RoleTile({required this.role, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, text) = _roleInfo[role]!;
    return Tap(
      onTap: onTap,
      sound: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? Color.alphaBlend(c.brandSoft.withValues(alpha: .6), c.surface) : c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? c.brand : c.line, width: on ? 1.6 : 1),
          boxShadow: on ? c.liftHi : c.lift,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 46,
              height: 46,
              decoration: BoxDecoration(gradient: on ? G.btn : null, color: on ? null : c.brandSoft, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: HIcon(icon, size: 22, color: on ? Colors.white : c.brandText),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role.label, style: T.ttl(context)),
                  const SizedBox(height: 2),
                  Text(text, style: T.sm(context).copyWith(color: c.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? c.brand : Colors.transparent,
                border: Border.all(color: on ? c.brand : c.line, width: 2),
              ),
              alignment: Alignment.center,
              child: on ? const HIcon('check', size: 14, stroke: 3, color: Colors.white) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// "I agree to the HOLA terms of use and privacy policy." with both names as links.
/// Tapping a link opens the page; tapping elsewhere on the row ticks the box.
class _TermsText extends StatefulWidget {
  const _TermsText();
  @override
  State<_TermsText> createState() => _TermsTextState();
}

class _TermsTextState extends State<_TermsText> {
  late final _terms = TapGestureRecognizer()..onTap = () => pushPage(context, const LegalPage.terms());
  late final _privacy = TapGestureRecognizer()..onTap = () => pushPage(context, const LegalPage.privacy());

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = T.sm(context).copyWith(color: context.c.brandText, fontWeight: FontWeight.w600, decoration: TextDecoration.underline);
    return Text.rich(
      TextSpan(
        style: T.sm(context).copyWith(color: context.c.ink),
        children: [
          TextSpan(text: tr('I agree to the HOLA ')),
          TextSpan(text: tr('terms of use'), style: link, recognizer: _terms),
          TextSpan(text: tr(' and ')),
          TextSpan(text: tr('privacy policy'), style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}
