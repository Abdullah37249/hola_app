import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/auth/auth.dart';
import '../features/salon/salon.dart';
import 'shell.dart';
import 'viewmodels/session_view_model.dart';

/// Splash while the database loads, then welcome/sign-in, salon set-up for a
/// new owner, or the role's tab shell (cross-faded).
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool _splash = true, _offering = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionViewModel>();
    // Just signed in with a password: ask once about fingerprint sign-in.
    if (s.offerFingerprint && s.splashDone && !_offering && !s.locked) {
      _offering = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await offerFingerprint(context);
        _offering = false;
      });
    }
    final Widget body = !s.ready
        ? const SizedBox()
        : !s.signedIn
        ? const WelcomeView(key: ValueKey('welcome'))
        : s.locked
        ? const FingerprintLockView(key: ValueKey('locked'))
        : s.needsSalonSetup
        ? const SalonSetupPage(key: ValueKey('setup'))
        : Shell(key: ValueKey('shell-${s.account!.id}'));
    return Stack(
      children: [
        AnimatedSwitcher(duration: const Duration(milliseconds: 420), child: body),
        if (_splash)
          SplashView(
            ready: s.ready,
            onDone: () {
              setState(() => _splash = false);
              s.splashFinished();
            },
          ),
      ],
    );
  }
}
