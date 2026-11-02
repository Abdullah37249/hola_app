import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app/di.dart';
import 'app/root.dart';
import 'core/l10n/l10n.dart';
import 'core/theme/theme.dart';
import 'core/utils/photo_files.dart';
import 'app/viewmodels/session_view_model.dart';
import 'shared/widgets/fx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PhotoFiles.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(MultiProvider(providers: appProviders(), child: const HolaApp()));
}

class HolaApp extends StatefulWidget {
  const HolaApp({super.key});
  @override
  State<HolaApp> createState() => _HolaAppState();
}

class _HolaAppState extends State<HolaApp> {
  @override
  void initState() {
    super.initState();
    L10n.lang.addListener(_relabel);
  }

  @override
  void dispose() {
    L10n.lang.removeListener(_relabel);
    super.dispose();
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
