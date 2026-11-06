import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/app/shell.dart';
import 'package:hola_professional/app/tabs.dart';
import 'package:hola_professional/app/viewmodels/session_view_model.dart';
import 'package:hola_professional/domain/repositories/repositories.dart';
import 'package:hola_professional/features/chat/chat.dart';
import 'package:hola_professional/features/customer/customer.dart';
import 'package:hola_professional/features/notifications/notifications.dart';
import 'package:hola_professional/features/profile/views/permissions_page.dart';
import 'package:hola_professional/features/rider/rider.dart';
import 'package:hola_professional/features/salon/salon.dart';
import 'package:hola_professional/features/trade/trade.dart';
import 'package:hola_professional/main.dart' as app;
import 'package:hola_professional/shared/widgets/fx.dart' show pushPage;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

/// Read-only sweep of the real app on a phone against HOLA staging: signs in
/// as each role, opens every tab and the main screens, screenshots each and
/// records rendering errors and failed syncs. Creates nothing on the server.
///
///   flutter drive -d PHONE_ID --driver=test_driver/integration_test.dart \
///     --target=integration_test/device_sweep_test.dart --dart-define=QA_PW=...
const _pw = String.fromEnvironment('QA_PW');
const _salon = '01a19f9f-035f-717a-85f4-1e3ba0fe1e94'; // Diamond Glamor Saloon
const _booking = '01a1af00-bc4b-71b8-88b2-260914fc7ff1'; // HB-002478
const _order = '01a1af08-2034-713c-9283-101cfe79087d'; // HO-000019
const _return = '01a1af28-11cc-7725-a72f-0d81f84c2c5b'; // HR-000002

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device sweep', (tester) async {
    expect(_pw, isNotEmpty, reason: 'pass --dart-define=QA_PW=...');
    final problems = <String>[];
    final failedSyncs = <String>[];
    final shots = <String>[];
    final images = <String, String>{};
    var current = 'start';

    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    app.main();
    await wait(4000);
    final print0 = debugPrint;
    debugPrint = (m, {wrapWidth}) {
      if (m != null && RegExp('failed|Error|error', caseSensitive: false).hasMatch(m)) failedSyncs.add('[$current] $m');
      print0(m, wrapWidth: wrapWidth);
    };

    final ctx = tester.element(find.byType(MaterialApp));
    final auth = ctx.read<AuthRepository>();
    final session = ctx.read<SessionViewModel>();

    // Errors (rendering or from background work) are collected after each
    // screen instead of ending the run: the sweep reports them all.
    void collect() {
      for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
        problems.add('[$current] ${'$e'.split('\n').first}');
      }
    }

    Future<void> shot(String name) async {
      current = name;
      await wait(2500);
      collect();
      // Captured inside the app (iOS doesn't deliver integration_test
      // screenshots): the frame as Flutter drew it, at 1x to keep it small.
      final view = tester.binding.renderViews.first;
      final image = await (view.debugLayer! as OffsetLayer).toImage(view.paintBounds, pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      images[name] = base64Encode(png!.buffer.asUint8List());
      shots.add(name);
    }

    // After an account switch the old shell may still be fading out: use the newest.
    BuildContext shell() => tester.element(find.byType(Shell, skipOffstage: false).last);

    Future<void> page(String name, Widget w) async {
      pushPage(shell(), w);
      await shot(name);
      Navigator.of(shell()).pop();
      await wait(600);
    }

    Future<void> signIn(String email) async {
      session.locked = false; // the sweep signs in with a password, not Face ID
      if (auth.current != null) await auth.signOut();
      await wait(1500);
      await auth.signIn(email, _pw);
      await wait(7000); // first sync from HOLA
      // The one-time "Allow access" intro: close it so the tabs show (the
      // permission screen itself is captured on its own below).
      for (var i = 0; i < 3 && find.byType(PermissionsPage).evaluate().isNotEmpty; i++) {
        Navigator.of(tester.element(find.byType(PermissionsPage).first)).pop();
        await wait(800);
      }
      // Wait until only the new account's shell is left.
      for (var i = 0; i < 50 && find.byType(Shell, skipOffstage: false).evaluate().length > 1; i++) {
        await wait(200);
      }
    }

    Future<void> tabs(String prefix) async {
      for (final (i, t) in tabsFor[session.rk]!.indexed) {
        session.setTab(t.id);
        await shot('${prefix}_${i + 1}_${t.id}');
      }
      session.setTab(tabsFor[session.rk]!.first.id);
      await wait(500);
    }

    await signIn('m.arslanhaider2001@gmail.com');
    await tabs('10_customer');
    await page('11_customer_salon', const SalonPage(id: _salon));
    await page('12_customer_booking', const BookingDetailPage(id: _booking));
    await page('13_customer_offers', const CustomerOffersPage());
    await page('14_customer_notifications', const NotificationsPage());
    await page('15_customer_messages', const MessagesPage());
    await page('16_customer_permissions', const PermissionsPage());

    await signIn('fatima@gmail.com');
    await tabs('20_salon');
    await page('21_salon_orders', const SalonOrdersPage(salonId: _salon));
    await page('22_salon_order', const OrderDetailPage(id: _order));
    await page('23_salon_new_order', const NewOrderPage(salonId: _salon));
    await page('24_salon_statement', const StatementPage(salonId: _salon));
    await page('25_salon_pay', const PayOutstandingPage(salonId: _salon));
    await page('26_salon_returns', const ReturnsPage(salonId: _salon));
    await page('27_salon_return', const ReturnDetailPage(id: _return));
    await page('28_salon_offers_hola', const OffersPage(salonId: _salon));
    await page('29_salon_reviews', const ReviewsPage());
    await page('30_salon_clients', const ClientsPage());
    await page('31_salon_profile', const SalonProfilePage());
    await page('32_salon_own_offers', const SalonOffersPage());
    await page('33_salon_training', const TrainingListPage());
    await page('34_salon_messages', const MessagesPage());

    await signIn('m.arslanhaider@gmail.com');
    await tabs('40_rider');
    await page('41_rider_delivery', const DeliveryPage(id: _order));

    await auth.signOut();
    await wait(1500);
    collect();
    debugPrint = print0;
    binding.reportData = {'images': images, 'screens': shots, 'renderProblems': problems.toSet().toList(), 'failedSyncs': failedSyncs.toSet().toList()};
  });
}
