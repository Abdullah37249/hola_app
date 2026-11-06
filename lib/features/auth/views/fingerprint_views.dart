import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/viewmodels/session_view_model.dart';
import '../../../core/security/biometrics.dart';
import '../../../core/utils/sfx.dart';
import '../../../domain/entities/entities.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/logo.dart';
import '../../../shared/widgets/ui.dart';
import '../widgets/auth_widgets.dart';

/// What to tell the person after a fingerprint check that didn't pass.
String? fingerprintProblem(BioResult r) => switch (r) {
  BioResult.ok || BioResult.cancelled => null,
  BioResult.failed => bio(tr('Fingerprint not recognised. Try again, or use your password.')),
  BioResult.lockedOut =>
    Platform.isIOS
        ? bio(tr('Face ID is locked after too many tries. Lock your iPhone and unlock it with your passcode, then try again.'))
        : tr('Too many tries. Use your password, or try your fingerprint again later.'),
  BioResult.unavailable =>
    Platform.isIOS
        ? bio(tr('Face ID is off for HOLA. Turn it on in Settings → HOLA → Face ID, or use your password.'))
        : tr('No fingerprint is set up on this phone. Add one in the phone’s Settings, or use your password.'),
};

/// The big round fingerprint button.
class FingerprintButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool busy;
  const FingerprintButton({super.key, this.onTap, this.busy = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tap(
      onTap: busy ? null : onTap,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: G.btn,
          boxShadow: const [BoxShadow(color: Color(0x992F80FF), blurRadius: 28, spreadRadius: -6, offset: Offset(0, 10))],
          border: Border.all(color: c.surface.withValues(alpha: .4), width: 2),
        ),
        alignment: Alignment.center,
        child: busy ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : HIcon(bioIcon, size: 46, color: Colors.white),
      ),
    );
  }
}

/// Shown when the app opens with fingerprint sign-in on: a fingerprint
/// unlocks it, or the person signs in with their password instead.
class FingerprintLockView extends StatefulWidget {
  const FingerprintLockView({super.key});
  @override
  State<FingerprintLockView> createState() => _LockState();
}

class _LockState extends State<FingerprintLockView> {
  bool _busy = false, _prompted = false;
  String? _problem;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _autoPrompt();
  }

  /// Asks for the fingerprint once, as soon as the splash has gone.
  void _autoPrompt() {
    final s = context.read<SessionViewModel>();
    if (_prompted || !s.splashDone) return;
    _prompted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final r = await context.read<SessionViewModel>().unlock();
    if (!mounted) return;
    if (r == BioResult.ok) Sfx.success();
    setState(() {
      _busy = false;
      _problem = fingerprintProblem(r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionViewModel>();
    _autoPrompt();
    final c = context.c;
    return AuthScaffold(
      children: [
        AuthHeading(
          top: const Center(child: Logo(height: 54, white: true)),
          title: tr('Welcome back, {name}', {'name': s.account?.firstName ?? ''}),
          sub: bio(tr('Use your fingerprint to open HOLA.')),
        ),
        const SizedBox(height: 28),
        AuthCard(
          children: [
            const SizedBox(height: 6),
            Center(
              child: FingerprintButton(onTap: _unlock, busy: _busy),
            ),
            const SizedBox(height: 14),
            Text(bio(tr('Touch the fingerprint sensor')), textAlign: TextAlign.center, style: T.ttl(context)),
            if (_problem case final p?) ...[
              const SizedBox(height: 8),
              Text(
                p,
                textAlign: TextAlign.center,
                style: T.sm(context).copyWith(color: c.badInk),
              ),
            ],
            const SizedBox(height: 8),
            HButton(bio(tr('Try fingerprint again')), icon: bioIcon, block: true, onTap: _busy ? null : _unlock),
            HButton(
              tr('Sign in with password instead'),
              kind: BtnKind.secondary,
              block: true,
              onTap: _busy
                  ? null
                  : () {
                      Sfx.tap();
                      s.usePasswordInstead();
                    },
            ),
          ],
        ),
      ],
    );
  }
}

/// The fingerprint icon next to Sign in, always shown. One saved account: a
/// fingerprint signs it in. Several: the person picks which, then touches.
/// None yet: it says to sign in with email and password first.
class FingerprintSignInButton extends StatelessWidget {
  /// The rider sign-in screen offers rider accounts only.
  final bool riders;

  /// After a successful sign-in (e.g. close the rider sign-in screen).
  final VoidCallback? onSignedIn;
  const FingerprintSignInButton({super.key, this.riders = false, this.onSignedIn});

  Future<void> _go(BuildContext context) async {
    final s = context.read<SessionViewModel>();
    if (!s.bioAvailable) {
      Sfx.error();
      Fx.toast(fingerprintProblem(BioResult.unavailable)!, icon: 'alert', tone: 'bad');
      return;
    }
    final all = s.fingerprintAccounts(riders: riders);
    if (all.isEmpty) {
      Sfx.tap();
      Fx.toast(bio(tr('Please log in first using your email and password to enable fingerprint login.')), icon: bioIcon, tone: 'info');
      return;
    }
    final pick = all.length == 1 ? all.first : await _pickAccount(context, all);
    if (pick == null) return;
    var r = BioResult.cancelled;
    final ok = await attempt(() async => r = await s.signInWithFingerprint(pick.accountId));
    if (!ok) return;
    if (r == BioResult.ok) {
      Sfx.success();
      Fx.toast(tr('Welcome back, {name}', {'name': s.account?.firstName ?? pick.firstName}));
      onSignedIn?.call();
    } else if (fingerprintProblem(r) case final p?) {
      Sfx.error();
      Fx.toast(p, icon: 'alert', tone: 'bad');
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: bio(tr('Sign in with fingerprint')),
    child: SizedBox(
      width: 56,
      child: HButton('', icon: bioIcon, kind: BtnKind.secondary, onTap: () => _go(context)),
    ),
  );
}

/// Several accounts on this phone have fingerprint sign-in: which one?
Future<FingerprintAccount?> _pickAccount(BuildContext context, List<FingerprintAccount> all) => showHSheet<FingerprintAccount>(
  context,
  (ctx) => VStack(gap: 12, [
    SheetHead(bio(tr('Sign in with fingerprint')), sub: bio(tr('Choose the account, then touch the fingerprint sensor.'))),
    Group(
      children: [
        for (final f in all)
          MRow(
            icon: switch (f.role) {
              'rider' => 'truck',
              'salonOwner' || 'salonStaff' => 'store',
              _ => 'user',
            },
            title: f.name,
            sub: f.email,
            onTap: () => Navigator.pop(ctx, f),
          ),
      ],
    ),
  ]),
);

/// Asked once, right after the first password sign-in on this phone.
Future<void> offerFingerprint(BuildContext context) async {
  final s = context.read<SessionViewModel>();
  final yes = await showHSheet<bool>(
    context,
    (ctx) => VStack(gap: 14, [
      const Center(child: FingerprintButton()),
      SheetHead(bio(tr('Sign in with your fingerprint?')), sub: bio(tr('Next time, open HOLA with your fingerprint instead of typing your password. You can turn this off any time in Settings.'))),
      HButton(bio(tr('Use fingerprint')), icon: bioIcon, block: true, onTap: () => Navigator.pop(ctx, true)),
      HButton(tr('Not now'), kind: BtnKind.ghost, block: true, onTap: () => Navigator.pop(ctx, false)),
    ]),
  );
  if (yes != true) {
    await s.declineFingerprint();
    return;
  }
  final r = await s.enableFingerprint();
  if (r == BioResult.ok) {
    Sfx.success();
    Fx.toast(bio(tr('Fingerprint sign-in is on')), icon: bioIcon);
  } else if (fingerprintProblem(r) case final p?) {
    Fx.toast(p, icon: 'alert', tone: 'bad');
  }
}

/// The Settings switch: on asks for a fingerprint first; off just turns it off.
Future<void> toggleFingerprint(BuildContext context, bool on) async {
  final s = context.read<SessionViewModel>();
  if (!on) {
    await s.disableFingerprint();
    Fx.toast(bio(tr('Fingerprint sign-in is off')), icon: bioIcon);
    return;
  }
  final r = await s.enableFingerprint();
  if (r == BioResult.ok) {
    Sfx.success();
    Fx.toast(bio(tr('Fingerprint sign-in is on')), icon: bioIcon);
  } else if (fingerprintProblem(r) case final p?) {
    Fx.toast(p, icon: 'alert', tone: 'bad');
  }
}
