import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'domain/entities/entities.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app/di.dart';
import 'app/links.dart';
import 'features/chat/chat.dart';
import 'features/chat/viewmodels/chat_view_models.dart' show ChatViewModel;
import 'core/push/push_service.dart';
import 'core/push/reminders.dart';
import 'app/reminder_sync.dart';
import 'features/customer/customer.dart' show BookingDetailPage;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'domain/repositories/repositories.dart';
import 'core/network/api.dart';
import 'app/root.dart';
import 'core/l10n/l10n.dart';
import 'core/theme/theme.dart';
import 'core/utils/maps.dart';
import 'core/utils/photo_files.dart';
import 'app/viewmodels/session_view_model.dart';
import 'shared/widgets/fx.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Release builds keep the device log quiet (no ids or server details).
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};
  // Safety net: an error from background work nobody awaited (a sync, a
  // fire-and-forget call) is logged instead of reaching the zone unhandled.
  // Screen errors still go through FlutterError's own handler.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };
  // Hold the first frame until the splash logo is decoded (a few ms), so the
  // hand-over from the phone's launch screen never shows a frame without it.
  binding.deferFirstFrame();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // The splash draws first: nothing here waits for set-up or the network.
  // Photo storage and Firebase start alongside it; push turns on once
  // Firebase is up. (Firebase reads android/app/google-services.json; iOS
  // has no config yet, so a failure must not stop the app.)
  unawaited(PhotoFiles.init());
  final firebase = Firebase.initializeApp().then<bool>(
    (_) {
      FirebaseMessaging.onBackgroundMessage(pushInBackground);
      return true;
    },
    onError: (Object e) {
      debugPrint('Firebase not started: $e');
      return false;
    },
  );
  final api = HolaApi();
  runApp(
    MultiProvider(
      providers: appProviders(api: api),
      child: HolaApp(pushApi: api, firebase: firebase),
    ),
  );
  _precacheLogo().timeout(const Duration(milliseconds: 500), onTimeout: () {}).whenComplete(binding.allowFirstFrame);
}

/// Loads the logo into the image cache that the splash draws from.
Future<void> _precacheLogo() {
  final done = Completer<void>();
  final stream = const AssetImage('assets/images/logo.png').resolve(ImageConfiguration.empty);
  late final ImageStreamListener l;
  l = ImageStreamListener(
    (_, _) {
      stream.removeListener(l);
      if (!done.isCompleted) done.complete();
    },
    onError: (_, _) {
      stream.removeListener(l);
      if (!done.isCompleted) done.complete();
    },
  );
  stream.addListener(l);
  return done.future;
}

class HolaApp extends StatefulWidget {
  const HolaApp({super.key, this.pushApi, this.firebase});

  /// Turns on push notifications once [firebase] has started (null in tests).
  final HolaApi? pushApi;

  /// Completes with whether Firebase started; push waits for it.
  final Future<bool>? firebase;
  @override
  State<HolaApp> createState() => _HolaAppState();
}

class _HolaAppState extends State<HolaApp> {
  @override
  void initState() {
    super.initState();
    L10n.lang.addListener(_relabel);
    ChatPage.openContext = openLink;
    Fx.navigatorKey = _nav; // a tapped, cut-off toast opens its full text
    final api = widget.pushApi;
    widget.firebase?.then((ok) {
      if (ok && api != null && mounted) _startPush(api);
    });
    // Booking reminders: kept in step with the customer's bookings.
    if (widget.pushApi != null) {
      _reminders = ReminderSync(context);
      Reminders.instance.tapped.addListener(_openReminder);
      context.read<SessionViewModel>().addListener(_openReminder);
    }
  }

  ReminderSync? _reminders;

  /// A tapped reminder, once someone is signed in and past the splash.
  Future<void> _openReminder() async {
    final tap = Reminders.instance.tapped.value;
    final session = context.read<SessionViewModel>();
    if (tap == null || !session.ready || !session.signedIn) return;
    Reminders.instance.tapped.value = null;
    final maps = tap.action == Reminders.directions ? safeMapsLink(tap.mapsUrl) : null;
    if (maps != null) {
      final ok = await launchUrl(maps, mode: LaunchMode.externalApplication);
      if (ok) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 600)); // let the splash and shell settle
    final ctx = _nav.currentContext;
    if (ctx != null && ctx.mounted) pushPage(ctx, BookingDetailPage(id: tap.appointmentId, askCancel: tap.action == Reminders.cancel));
  }

  void _startPush(HolaApi api) {
    final push = _push = PushService(api: api, auth: context.read<AuthRepository>(), engage: context.read<EngagementRepository>());
    push.onForeground = (title, body, link) {
      // The conversation on screen shows the message itself.
      if (link?.type == 'chat' && link?.id == ChatViewModel.openThreadId) return;
      // iPhone already shows the system banner for it (see PushService.start).
      if (Platform.isIOS) return;
      Fx.toast(title.isNotEmpty ? '$title: $body' : body, icon: link?.type == 'chat' ? 'msg' : 'bell', tone: 'info');
    };
    push.opened.addListener(_openPush);
    context.read<SessionViewModel>().addListener(_openPush);
    push.start();
  }

  PushService? _push;
  final _nav = GlobalKey<NavigatorState>();

  @override
  void dispose() {
    L10n.lang.removeListener(_relabel);
    _reminders?.dispose();
    Reminders.instance.tapped.removeListener(_openReminder);
    super.dispose();
  }

  /// Opens a tapped push once someone is signed in and past the splash.
  Future<void> _openPush() async {
    final push = _push;
    final link = push?.opened.value;
    final session = context.read<SessionViewModel>();
    if (push == null || link == null || !session.ready || !session.signedIn || session.needsSalonSetup || session.awaitingApproval) return;
    push.opened.value = null;
    // Fresh data for the screen the push points at.
    try {
      if (link.type == 'chat') {
        final chat = context.read<ChatRepository>();
        await chat.sync().timeout(const Duration(seconds: 8));
        await chat.syncThread(link.id).timeout(const Duration(seconds: 8));
      } else if (link.type == 'collection' && session.account?.role == Role.rider) {
        await context.read<TradeRepository>().syncCollections().timeout(const Duration(seconds: 8));
      } else if (link.type == 'order' && session.account?.role == Role.rider) {
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
