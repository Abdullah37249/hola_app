import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/app/di.dart';
import 'package:hola_professional/app/tabs.dart';
import 'package:hola_professional/app/viewmodels/session_view_model.dart';
import 'package:hola_professional/core/utils/sfx.dart';
import 'package:hola_professional/data/local/storage.dart';
import 'package:hola_professional/domain/entities/entities.dart';
import 'package:hola_professional/domain/repositories/repositories.dart';
import 'package:hola_professional/main.dart';
import 'package:hola_professional/shared/widgets/ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hola_professional/data/local/local_auth_repository.dart';

/// Boots the app on an in-memory database, signs up each role for real and
/// opens every tab, on a typical phone, a small phone and with large text.
void main() {
  // Settings live in SharedPreferences; tests use an in-memory store.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    Sfx.enabled = false;
    // Use the real font so layout widths match the device.
    final font = FontLoader('InstrumentSans')..addFont(rootBundle.load('assets/fonts/InstrumentSans.ttf'));
    await font.load();
  });

  const screens = [('phone', Size(1170, 2532), 3.0, 1.0), ('small', Size(1080, 1920), 3.0, 1.0), ('large text', Size(1170, 2532), 3.0, 1.3)];
  const pw = 'secret-pass-1';

  /// Signs up [role] (plus whatever it needs to have a populated experience).
  Future<void> prepare(BuildContext ctx, Role role) async {
    final auth = ctx.read<AuthRepository>(), salons = ctx.read<SalonRepository>();
    // Officers and riders come from HOLA: create them, then sign in like the app does.
    Future<void> up(Role r, String email) async {
      if (Role.signUp.contains(r)) {
        await auth.signUp(role: r, name: 'Test ${r.name}', email: email, phone: '0300 1234567', password: pw, city: 'Lahore');
      } else {
        await (auth as LocalAuthRepository).provision(role: r, name: 'Test ${r.name}', email: email, phone: '0300 1234567', password: pw, city: 'Lahore');
        await auth.signIn(email, pw);
      }
    }

    // An active salon with a service and a staff member exists in every scenario.
    await up(Role.salesOfficer, 'officer@t.pk');
    await up(Role.salonOwner, 'owner@t.pk');
    final s = await salons.createSalon(name: 'Maison Test', phone: '0300 1112223', about: 'Hair and colour.', branchName: 'Main', address: '1 Main Blvd', area: 'Gulberg', city: 'Lahore');
    await salons.saveService(salonId: s.id, name: 'Cut & blow-dry', category: 'Hair', description: '', price: 3500, durationMin: 60);
    await salons.addStaff(s.id, name: 'Test Staff', phone: '0300 2223334', title: 'Stylist');
    await auth.signIn('officer@t.pk', pw);
    await salons.approveSalon(s.id);
    switch (role) {
      case Role.customer:
        await up(Role.customer, 'cust@t.pk');
      case Role.salonOwner:
        await auth.signIn('owner@t.pk', pw);
      case Role.salonStaff:
        break; // team members don't sign in
      case Role.salesOfficer:
        break;
      case Role.rider:
        await up(Role.rider, 'rider@t.pk');
      case Role.trainer:
        await up(Role.trainer, 'trainer@t.pk');
    }
  }

  testWidgets('form errors show under their field and clear on typing', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: appProviders(storage: MemoryStorage()),
        child: const HolaApp(),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100)); // splash
    }
    await tester.tap(find.text('Create an account'));
    await settle(tester);
    await tester.tap(find.text('Customer'));
    await tester.pump();
    await tester.tap(find.text('Continue as customer'));
    await settle(tester);

    Finder input(String label) => find.descendant(of: find.widgetWithText(HField, label), matching: find.byType(TextFormField));
    await tester.enterText(input('Full name'), 'Test Customer');
    await tester.enterText(input('Email'), 'not-an-email');
    await tester.enterText(input('Phone'), '0300 1234567');
    await tester.enterText(input('City'), 'Lahore');
    await tester.enterText(input('Password'), pw);
    await tester.ensureVisible(find.textContaining('I agree'));
    await tester.tap(find.textContaining('I agree'));
    await tester.pump();
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pump(const Duration(seconds: 1));

    const msg = 'Enter a valid email address.';
    expect(find.descendant(of: find.widgetWithText(HField, 'Email'), matching: find.text(msg)), findsOneWidget);
    await tester.enterText(input('Email'), 'cust@t.pk');
    await tester.pump();
    expect(find.text(msg), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  for (final (screen, size, dpr, scale) in screens) {
    for (final role in Role.values.where((r) => r != Role.salonStaff)) {
      testWidgets('renders every tab: ${role.name} on $screen', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = dpr;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        // Report where a layout error happened, not just that one did.
        final report = FlutterError.onError;
        FlutterError.onError = (d) {
          final at = d.informationCollector?.call().map((x) => x.toString()).firstWhere((x) => x.contains('lib/'), orElse: () => '') ?? '';
          debugPrint('LAYOUT ERROR [$screen ${role.name}] ${d.exceptionAsString().split('\n').first} ${at.trim()}');
          report?.call(d);
        };
        addTearDown(() => FlutterError.onError = report);

        await tester.pumpWidget(
          MultiProvider(
            providers: appProviders(storage: MemoryStorage()),
            child: const HolaApp(),
          ),
        );
        await tester.pump(const Duration(seconds: 3)); // splash + DB load
        final ctx = tester.element(find.byType(HolaApp));
        await tester.runAsync(() => prepare(ctx, role));
        await tester.pump(const Duration(seconds: 1));

        final session = ctx.read<SessionViewModel>();
        expect(session.account?.role, role);
        for (final tab in tabsFor[session.rk]!) {
          session.setTab(tab.id);
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull, reason: '${session.rk}.${tab.id}');
        }

        // Let pending animation/toast timers finish before the tree is torn down.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}

/// The glowing ring never stops turning, so wait a fixed second instead of
/// for all animation to end.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
