// Renders every main screen of every role to PNGs for design review:
//   flutter test test/screens_test.dart --update-goldens
// Images land in test/screens/. The scenario data below exists only in this test.
// Dark theme: add --dart-define=DARK=true; images land in test/screens_dark/.
// Urdu: add --dart-define=LANG=ur; images land in test/screens_ur/.
@Tags(['screens'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/app/di.dart';
import 'package:hola_professional/app/shell.dart';
import 'package:hola_professional/app/tabs.dart';
import 'package:hola_professional/app/viewmodels/session_view_model.dart';
import 'package:hola_professional/core/utils/clock.dart';
import 'package:hola_professional/core/utils/sfx.dart';
import 'package:hola_professional/data/local/storage.dart';
import 'package:hola_professional/domain/entities/entities.dart';
import 'package:hola_professional/domain/repositories/repositories.dart';
import 'package:hola_professional/features/chat/chat.dart';
import 'package:hola_professional/features/customer/customer.dart';
import 'package:hola_professional/features/field/field.dart';
import 'package:hola_professional/features/legal/views/legal_page.dart';
import 'package:hola_professional/features/notifications/notifications.dart';
import 'package:hola_professional/features/rider/rider.dart';
import 'package:hola_professional/features/salon/salon.dart';
import 'package:hola_professional/features/trade/trade.dart';
import 'package:hola_professional/main.dart';
import 'package:hola_professional/shared/widgets/fx.dart';
import 'package:provider/provider.dart';

const pw = 'secret-pass-1';
const dark = bool.fromEnvironment('DARK');
const lang = String.fromEnvironment('LANG', defaultValue: 'en');
const shotDir = lang == 'ur' ? 'screens_ur' : dark ? 'screens_dark' : 'screens';

class Ids {
  late String salon, branch, appt, done, order, visit, training, thread;
}

/// A believable day across all roles, created through the real repositories.
Future<Ids> scenario(BuildContext ctx) async {
  final ids = Ids();
  final auth = ctx.read<AuthRepository>(), salons = ctx.read<SalonRepository>(), book = ctx.read<BookingRepository>();
  final eng = ctx.read<EngagementRepository>(), trade = ctx.read<TradeRepository>(), field = ctx.read<FieldRepository>();
  Future<Account> up(Role r, String name, String email) => auth.signUp(role: r, name: name, email: email, phone: '0300 1234567', password: pw, city: 'Lahore');
  Future<void> as(String e) => auth.signIn(e, pw);

  await up(Role.salesOfficer, 'Bilal Ahmed', 'officer@t.pk');
  final rider = await up(Role.rider, 'Usman Ali', 'rider@t.pk');
  await up(Role.salonOwner, 'Noor Fatima', 'owner@t.pk');
  final s = await salons.createSalon(name: 'Maison Noor', phone: '0300 1112223', about: 'Hair, colour and bridal studio in the heart of Gulberg.', branchName: 'Gulberg', address: '12-B Main Boulevard', area: 'Gulberg III', city: 'Lahore');
  ids.salon = s.id;
  ids.branch = salons.branches(s.id).single.id;
  final cut = await salons.saveService(salonId: s.id, name: 'Signature cut & blow-dry', category: 'Hair', description: 'Consultation, wash, cut and finish.', price: 3500, durationMin: 60);
  final colour = await salons.saveService(salonId: s.id, name: 'Root touch-up', category: 'Colour', description: '', price: 6500, durationMin: 90);
  await salons.saveService(salonId: s.id, name: 'Gel manicure', category: 'Nails', description: '', price: 2800, durationMin: 45);
  await salons.saveService(salonId: s.id, name: 'HydraFacial', category: 'Skin', description: '', price: 9000, durationMin: 60);
  await salons.addStaff(s.id, name: 'Ayesha Malik', email: 'staff@t.pk', phone: '0301 2223334', password: pw, title: 'Senior stylist');
  await salons.addStaff(s.id, name: 'Hamza Iqbal', email: 'hamza@t.pk', phone: '0301 2223335', password: pw, title: 'Colour specialist');
  await up(Role.salonOwner, 'Rabia Shah', 'owner2@t.pk');
  final s2 = await salons.createSalon(name: 'Glow Bar', phone: '0300 3334445', about: 'Nails and skin.', branchName: '', address: '22-C Faisal Town', area: 'Faisal Town', city: 'Lahore');
  await salons.saveService(salonId: s2.id, name: 'Spa pedicure', category: 'Nails', description: '', price: 3200, durationMin: 60);

  await as('officer@t.pk');
  await salons.approveSalon(s.id);
  await trade.setCreditTerms(s.id, limit: 100000, days: 30);
  final p1 = await trade.saveProduct(name: 'Bond Repair Shampoo', category: 'Care', description: 'Sulphate-free cleanse that rebuilds bonds.', color: 0xFF005BAC, shape: '', variants: [Variant(id: 'a', name: '1 L', tradePrice: 2450, retailPrice: 3200, stock: 60)], schemeBuy: 6, schemeFree: 1);
  await trade.saveProduct(name: 'Colour Cream', category: 'Colour', description: 'Permanent colour, 60 ml.', color: 0xFF771913, shape: 'tube', variants: [Variant(id: 'b', name: '7.1 Ash Blonde', tradePrice: 950, retailPrice: 0, stock: 40), Variant(id: 'c', name: '6.0 Dark Blonde', tradePrice: 950, retailPrice: 0, stock: 25)], schemeBuy: 0, schemeFree: 0);
  await trade.saveProduct(name: 'Argan Glow Serum', category: 'Styling', description: 'Weightless shine serum.', color: 0xFFFF8A00, shape: 'drop', variants: [Variant(id: 'd', name: '100 ml', tradePrice: 1900, retailPrice: 2850, stock: 8)], schemeBuy: 0, schemeFree: 0);
  final v = await field.planVisit(salonId: s2.id, at: DateTime(2026, 11, 2, 13), purpose: 'Introduce colour range');
  ids.visit = v.id;
  await field.planVisit(salonId: s.id, at: DateTime(2026, 11, 2, 15, 30), purpose: 'Credit follow-up');
  final t = await field.saveTraining(title: 'Colour Mastery: Level 2', description: 'Toning, balayage and correction.', location: 'HOLA Academy, Gulberg', at: DateTime(2026, 11, 5, 11), durationMin: 180, seats: 12);
  ids.training = t.id;

  await up(Role.customer, 'Mariam Siddiqui', 'cust@t.pk');
  final a = await book.book(salonId: s.id, branchId: ids.branch, serviceIds: [cut.id], start: DateTime(2026, 11, 2, 16));
  ids.appt = a.id;
  final past = await book.book(salonId: s.id, branchId: ids.branch, serviceIds: [colour.id], start: DateTime(2026, 11, 2, 12));
  ids.done = past.id;
  await salons.toggleFavourite(s.id);
  final th = await eng.openThread(s.id);
  ids.thread = th.id;
  await eng.send(th.id, 'Hi! Do you have time for a keratin treatment this week?', asSalon: false);

  await as('owner@t.pk');
  await book.confirm(past.id);
  await eng.send(th.id, 'Yes, Thursday at 2 pm works. It takes about 3 hours.', asSalon: true);
  clock = () => DateTime(2026, 11, 2, 11, 55);
  await book.checkIn(past.id);
  await book.startService(past.id);
  await book.complete(past.id);
  clock = () => DateTime(2026, 11, 2, 11);
  final o = await trade.placeOrder(salonId: s.id, cart: [CartLine(p1.id, 'a', 12)], payment: PaymentMethod.credit);
  ids.order = o.id;
  await as('cust@t.pk');
  await eng.addReview(appointmentId: past.id, stars: 5, text: 'Ayesha is brilliant. Best colour I have had.');
  await as('officer@t.pk');
  await trade.approveOrder(o.id);
  await trade.dispatch(o.id, rider.id);
  return ids;
}

void main() {
  setUpAll(() async {
    Sfx.enabled = false;
    // Tests have no system font fallback, so Urdu would render as boxes. For a
    // readable Urdu review on a Mac, draw all text with a font that has both scripts.
    const both = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
    if (lang == 'ur' && File(both).existsSync()) {
      for (final family in ['InstrumentSans', 'DMSerifDisplay']) {
        await (FontLoader(family)..addFont(File(both).readAsBytes().then((b) => ByteData.view(b.buffer)))).load();
      }
    } else {
      await (FontLoader('InstrumentSans')..addFont(rootBundle.load('assets/fonts/InstrumentSans.ttf'))).load();
    }
  });

  testWidgets('screens', (tester) async {
    clock = () => DateTime(2026, 11, 2, 11); // Monday 11:00
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(providers: appProviders(storage: MemoryStorage('{"prefs":{"sound":false,"theme":"${dark ? 'dark' : 'light'}","language":"$lang"}}')), child: const HolaApp()));
    // Step through the animated splash frame by frame so it plays out and leaves.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    Future<void> shot(String name) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await expectLater(find.byType(HolaApp), matchesGoldenFile('$shotDir/$name.png'));
    }

    await shot('00_welcome');
    final ctx = tester.element(find.byType(HolaApp));
    final ids = (await tester.runAsync(() => scenario(ctx)))!;
    final auth = ctx.read<AuthRepository>();
    final session = ctx.read<SessionViewModel>();

    Future<void> signIn(String email) async {
      await tester.runAsync(() => auth.signIn(email, pw));
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> page(String name, Widget w) async {
      pushPage(tester.element(find.byType(Shell, skipOffstage: false)), w);
      await shot(name);
      Navigator.of(tester.element(find.byType(Shell, skipOffstage: false))).pop();
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> tabs(String prefix) async {
      for (final (i, t) in tabsFor[session.rk]!.indexed) {
        session.setTab(t.id);
        await shot('${prefix}_${i + 1}_${t.id}');
      }
      session.setTab(tabsFor[session.rk]!.first.id);
    }

    await signIn('cust@t.pk');
    await tabs('10_customer');
    await page('15_customer_salon', SalonPage(id: ids.salon));
    await page('16_customer_booking', BookingDetailPage(id: ids.appt));
    await page('17_customer_done', BookingDetailPage(id: ids.done));
    await page('18_customer_notifications', const NotificationsPage());
    await page('19_legal_terms', const LegalPage.terms());
    await page('19_customer_chat', ChatPage(threadId: ids.thread, asSalon: false));

    await signIn('owner@t.pk');
    await tabs('20_owner');
    await page('26_owner_appt', AppointmentDetailPage(id: ids.appt));
    await page('27_owner_orders', SalonOrdersPage(salonId: ids.salon));
    await page('28_owner_new_order', NewOrderPage(salonId: ids.salon));

    await signIn('staff@t.pk');
    await tabs('30_staff');

    await signIn('officer@t.pk');
    await tabs('40_officer');
    await page('46_officer_salon', SalonRecordPage(id: ids.salon));
    await page('47_officer_visit', VisitPage(id: ids.visit));
    await page('48_officer_order', OrderDetailPage(id: ids.order));

    await signIn('rider@t.pk');
    await tabs('50_rider');
    await page('54_rider_delivery', DeliveryPage(id: ids.order));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
