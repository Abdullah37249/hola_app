import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/core/utils/network_status.dart';
import 'package:hola_professional/core/utils/sfx.dart';
import 'package:hola_professional/shared/widgets/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loading, failure and offline states, plus the button's real busy state.
void main() {
  // Settings live in SharedPreferences; tests use an in-memory store.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    Sfx.enabled = false;
    final font = FontLoader('InstrumentSans')..addFont(rootBundle.load('assets/fonts/InstrumentSans.ttf'));
    await font.load();
  });

  Widget host(Widget child, {bool dark = false}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTheme(false),
    darkTheme: buildTheme(true),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, c) => FxHost(child: c!),
    home: Scaffold(
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );

  testWidgets('AsyncBody: placeholders, then error with retry, then content', (tester) async {
    var loading = true, hasData = false, retries = 0;
    Object? error;
    late StateSetter set;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, s) {
            set = s;
            return AsyncBody(loading: loading, hasData: hasData, error: error, onRetry: () async => retries++, builder: (_) => const Text('Content'));
          },
        ),
      ),
    );
    expect(find.byType(SkeletonList), findsOneWidget);

    // The shimmer and the error icon animate forever, so step time instead of settling.
    set(() => (loading, error) = (false, Exception('timeout')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Couldn't load"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(seconds: 1));
    expect(retries, 1);

    set(() => (error, hasData) = (null, true));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Content'), findsOneWidget);
    // A refresh keeps the content on screen instead of blanking to placeholders.
    set(() => loading = true);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Content'), findsOneWidget);
    expect(find.byType(SkeletonList), findsNothing);
  });

  testWidgets('a button ignores taps while its action is running', (tester) async {
    var runs = 0;
    final done = Completer<void>();
    await tester.pumpWidget(
      host(
        HButton(
          'Save',
          onTap: () {
            runs++;
            return done.future;
          },
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Save'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(runs, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // slow work shows a spinner
    done.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Save'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('renders the states (${dark ? 'dark' : 'light'})', (tester) async {
      tester.view.physicalSize = const Size(1179, 1800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      NetworkStatus.online.value = false;
      addTearDown(() => NetworkStatus.online.value = true);
      await tester.pumpWidget(
        host(
          dark: dark,
          Column(
            children: [
              const SizedBox(height: 40),
              const SkeletonList(count: 2),
              const SizedBox(height: 16),
              LoadError(onRetry: () async {}),
            ],
          ),
        ),
      );
      for (var i = 0; i < 9; i++) {
        await tester.pump(const Duration(milliseconds: 100)); // entrances and banner in, shimmer mid-sweep
      }
      expect(find.text("You're offline. Check your connection."), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/states_${dark ? 'dark' : 'light'}.png'));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
