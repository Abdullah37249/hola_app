import 'package:firebase_core/firebase_core.dart';
import 'domain/entities/entities.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app/di.dart';
import 'app/links.dart';
import 'core/push/push_service.dart';
import 'domain/repositories/repositories.dart';
import 'core/network/api.dart';
import 'app/root.dart';
import 'core/l10n/l10n.dart';
import 'core/theme/theme.dart';
import 'core/utils/photo_files.dart';
import 'app/viewmodels/session_view_model.dart';
import 'shared/widgets/fx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PhotoFiles.init();
  // Firebase reads android/app/google-services.json. iOS has no config yet,
  // so a failure there must not stop the app from starting.
  var firebase = false;
  try {
    await Firebase.initializeApp();
    firebase = true;
  } catch (e) {
    debugPrint('Firebase not started: $e');
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final api = HolaApi();
  runApp(
    MultiProvider(
      providers: appProviders(api: api),
      child: HolaApp(pushApi: firebase ? api : null),
    ),
  );
}

class HolaApp extends StatefulWidget {
  const HolaApp({super.key, this.pushApi});

  /// Turns on push notifications (null in tests and when Firebase didn't start).
  final HolaApi? pushApi;
  @override
  State<HolaApp> createState() => _HolaAppState();
}

class _HolaAppState extends State<HolaApp> {
  @override
  void initState() {
    super.initState();
    L10n.lang.addListener(_relabel);
    final api = widget.pushApi;
    if (api != null) {
      final push = _push = PushService(api: api, auth: context.read<AuthRepository>(), engage: context.read<EngagementRepository>());
      push.onForeground = (title, body, _) => Fx.toast(title.isNotEmpty ? title : body, icon: 'bell', tone: 'info');
      push.opened.addListener(_openPush);
      context.read<SessionViewModel>().addListener(_openPush);
      push.start();
    }
  }

  PushService? _push;
  final _nav = GlobalKey<NavigatorState>();

  @override
  void dispose() {
    L10n.lang.removeListener(_relabel);
    super.dispose();
  }

  /// Opens a tapped push once someone is signed in and past the splash.
  Future<void> _openPush() async {
    final push = _push;
    final link = push?.opened.value;
    final session = context.read<SessionViewModel>();
    if (push == null || link == null || !session.ready || !session.signedIn || session.needsSalonSetup) return;
    push.opened.value = null;
    // Fresh data for the screen the push points at.
    try {
      if (link.type == 'order' && session.account?.role == Role.rider) {
        await context.read<TradeRepository>().syncDeliveries().timeout(const Duration(seconds: 8));
      } else if (link.type == 'offers' && session.account?.salonId != null) {
        await context.read<TradeRepository>().syncCoupons(session.account!.salonId!).timeout(const Duration(seconds: 8));
      } else if (link.type == 'training') {
        await context.read<FieldRepository>().syncTrainings().timeout(const Duration(seconds: 8));
      } else if (link.type == 'payment' && session.account?.salonId != null) {
        final trade = context.read<TradeRepository>(), salonId = session.account!.salonId!;
        await Future.wait([trade.syncCredit(salonId), trade.syncPaymentRequests(salonId)]).timeout(const Duration(seconds: 8));
      } else if (link.type == 'order' && session.account?.salonId != null) {
        await context.read<TradeRepository>().syncOrders(session.account!.salonId!).timeout(const Duration(seconds: 8));
      }
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 900)); // let the splash and shell settle
    final ctx = _nav.currentContext;
    if (ctx != null && ctx.mounted) openLink(ctx, link);
  }

  /// Text comes from tr(), which isn't an inherited dependency, so a language
  /// change rebuilds every widget in place (open pages and state are kept).
  void _relabel() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    if (mounted) (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<SessionViewModel, ThemeMode>((s) => s.themeMode);
    final lang = context.select<SessionViewModel, String>((s) => s.language);
    return MaterialApp(
      title: 'HOLA Professional',
      navigatorKey: _nav,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(false),
      darkTheme: buildTheme(true),
      themeMode: mode,
      // Urdu turns the whole app right-to-left.
      locale: Locale(lang),
      supportedLocales: L10n.supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => FxHost(child: child!),
      home: const Root(),
    );
  }
}
