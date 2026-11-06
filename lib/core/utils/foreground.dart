import 'package:flutter/widgets.dart';

/// The app is on screen. Polling timers skip their work otherwise: nothing
/// is fetched or saved in the background (pushes still arrive), and the
/// shell refreshes everything when the app comes back.
bool get appInForeground {
  final s = WidgetsBinding.instance.lifecycleState;
  return s == null || s == AppLifecycleState.resumed;
}
