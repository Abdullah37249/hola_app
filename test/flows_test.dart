import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/core/security/sha256.dart';
import 'package:hola_professional/core/utils/clock.dart';
import 'package:hola_professional/data/local/local_auth_repository.dart';
import 'package:hola_professional/data/local/local_booking_repository.dart';
import 'package:hola_professional/data/local/local_database.dart';
import 'package:hola_professional/data/local/local_engagement_repository.dart';
import 'package:hola_professional/data/local/local_field_repository.dart';
import 'package:hola_professional/data/local/local_salon_repository.dart';
import 'package:hola_professional/data/local/local_trade_repository.dart';
import 'package:hola_professional/data/local/storage.dart';
import 'package:hola_professional/domain/entities/entities.dart';
import 'package:hola_professional/domain/repositories/repositories.dart';

/// End-to-end business flows across roles, on the real on-device repositories.
void main() {
  late MemoryStorage storage;
  late LocalDatabase db;
  late LocalAuthRepository auth;
  late LocalSalonRepository salons;
  late LocalBookingRepository bookings;
  late LocalEngagementRepository engage;
  late LocalTradeRepository trade;
  late LocalFieldRepository field;
  const pw = 'secret-pass-1';

  // Monday 2 Nov 2026, 09:00.
  final monday9 = DateTime(2026, 11, 2, 9);

  setUp(() async {
    clock = () => monday9;
    storage = MemoryStorage();
    db = LocalDatabase(storage);
    auth = LocalAuthRepository(db);
    salons = LocalSalonRepository(db);
    bookings = LocalBookingRepository(db);
    engage = LocalEngagementRepository(db);
    trade = LocalTradeRepository(db);
    field = LocalFieldRepository(db);
    await auth.init();
  });

  Future<Account> signUp(Role r, String name, String email) => auth.signUp(role: r, name: name, email: email, phone: '0300 1234567', password: pw);
  Future<void> as(String email) => auth.signIn(email, pw).then((_) {});

  /// Owner + active salon with one service; officer exists. Returns (salon, service).
  Future<(Salon, ServiceItem)> liveSalon() async {
    await signUp(Role.salesOfficer, 'Bilal Ahmed', 'officer@hola.pk');
    await signUp(Role.salonOwner, 'Noor Fatima', 'noor@salon.pk');
    final s = await salons.createSalon(name: 'Maison Noor', phone: '0300 1112223', about: '', branchName: 'Gulberg', address: '12 Main Blvd', area: 'Gulberg III', city: 'Lahore');
    final svc = await salons.saveService(salonId: s.id, name: 'Cut & blow-dry', category: 'Hair', description: '', price: 3500, durationMin: 60);
    await as('officer@hola.pk');
    await salons.approveSalon(s.id);
    return (s, svc);
  }

  test('sha256 matches the standard test vector', () {
    expect(sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(sha256Hex(''), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });

  test('accounts: sign up, wrong password, duplicate email, persistence', () async {
    await signUp(Role.customer, 'Mariam Siddiqui', 'Mariam@Example.com');
    expect(auth.current!.email, 'mariam@example.com');
    await auth.signOut();
    expect(() => auth.signIn('mariam@example.com', 'nope-nope'), throwsA(isA<DomainError>()));
    expect(() => signUp(Role.customer, 'Other', 'mariam@example.com'), throwsA(isA<DomainError>()));
    await as('mariam@example.com');
    await db.flush();
    final db2 = LocalDatabase(MemoryStorage(storage.data));
    final auth2 = LocalAuthRepository(db2);
    await auth2.init();
    expect(auth2.current?.name, 'Mariam Siddiqui'); // session survives restart
  });

  test('salon is listed once it has a service; verification adds the badge', () async {
    await signUp(Role.salesOfficer, 'Bilal', 'officer@hola.pk');
    await signUp(Role.salonOwner, 'Noor', 'noor@salon.pk');
    final s = await salons.createSalon(name: 'Maison Noor', phone: '0300 1112223', about: '', branchName: '', address: '12 Main Blvd', area: 'Gulberg III', city: 'Lahore');
    expect(salons.discover(), isEmpty); // no services yet
    await salons.saveService(salonId: s.id, name: 'Gel manicure', category: 'Nails', description: '', price: 2800, durationMin: 45);
    expect(salons.discover().single.id, s.id);
    expect(salons.salon(s.id)!.isActive, isFalse);
    await as('officer@hola.pk');
    expect(engage.notifications().map((n) => n.title), contains('New salon to verify'));
    await salons.approveSalon(s.id);
    expect(salons.discover(category: 'Nails').single.id, s.id);
    expect(salons.discover(query: 'gulberg manicure').single.id, s.id);
    expect(salons.discover(category: 'Hair'), isEmpty);
  });

  test('booking request → salon confirms → customer notified; slot is then taken', () async {
    final (s, svc) = await liveSalon();
    final cust = await signUp(Role.customer, 'Mariam', 'mariam@example.com');
    final branch = salons.branches(s.id).single;
    final slots = bookings.availability(branchId: branch.id, serviceIds: [svc.id], day: monday9);
    expect(slots.first.start, DateTime(2026, 11, 2, 10)); // opens 10:00, after 30-min lead
    final a = await bookings.book(salonId: s.id, branchId: branch.id, serviceIds: [svc.id], start: slots.first.start);
    expect(a.status, ApptStatus.requested);
    // Only one professional (the owner) → 10:00 no longer offered.
    expect(bookings.availability(branchId: branch.id, serviceIds: [svc.id], day: monday9).first.start, DateTime(2026, 11, 2, 11));
    expect(() => bookings.book(salonId: s.id, branchId: branch.id, serviceIds: [svc.id], start: a.startsAt), throwsA(isA<DomainError>()));

    await as('noor@salon.pk');
    expect(engage.notifications().first.title, 'New booking request');
    await bookings.confirm(a.id);
    await as('mariam@example.com');
    expect(bookings.forCustomer(cust.id).single.status, ApptStatus.confirmed);
    expect(engage.notifications().first.title, 'Booking confirmed');
  });

  test('late cancellation is flagged; free inside the window', () async {
    final (s, svc) = await liveSalon();
    await signUp(Role.customer, 'Mariam', 'mariam@example.com');
    final b = salons.branches(s.id).single;
    final a = await bookings.book(salonId: s.id, branchId: b.id, serviceIds: [svc.id], start: DateTime(2026, 11, 2, 10));
    await as('noor@salon.pk');
    await bookings.confirm(a.id);
    await as('mariam@example.com');
    await bookings.cancel(a.id, 'Running late'); // 1 h before, window is 2 h
    expect(bookings.appointment(a.id)!.lateCancel, isTrue);
  });

  test('visit lifecycle: check-in, complete, review, salon replies, rating', () async {
    final (s, svc) = await liveSalon();
    await signUp(Role.customer, 'Mariam', 'mariam@example.com');
    final b = salons.branches(s.id).single;
    final a = await bookings.book(salonId: s.id, branchId: b.id, serviceIds: [svc.id], start: DateTime(2026, 11, 2, 10));
    await as('noor@salon.pk');
    await bookings.confirm(a.id);
    clock = () => DateTime(2026, 11, 2, 9, 55);
    await bookings.checkIn(a.id);
    await bookings.startService(a.id);
    await bookings.complete(a.id);
    await as('mariam@example.com');
    final r = await engage.addReview(appointmentId: a.id, stars: 5, text: 'Lovely cut');
    expect(() => engage.addReview(appointmentId: a.id, stars: 4, text: ''), throwsA(isA<DomainError>()));
    await as('noor@salon.pk');
    await engage.replyToReview(r.id, 'Thank you, Mariam!');
    expect(salons.rating(s.id).average, 5);
    expect(salons.rating(s.id).count, 1);
  });

  test('no-show only after the grace period', () async {
    final (s, svc) = await liveSalon();
    await signUp(Role.customer, 'Mariam', 'mariam@example.com');
    final b = salons.branches(s.id).single;
    final a = await bookings.book(salonId: s.id, branchId: b.id, serviceIds: [svc.id], start: DateTime(2026, 11, 2, 10));
    await as('noor@salon.pk');
    await bookings.confirm(a.id);
    clock = () => DateTime(2026, 11, 2, 10, 10);
    expect(() => bookings.noShow(a.id), throwsA(isA<DomainError>()));
    clock = () => DateTime(2026, 11, 2, 10, 16);
    await bookings.noShow(a.id);
    expect(bookings.appointment(a.id)!.status, ApptStatus.noShow);
  });

  test('staff: added by owner, signs in, leave approved blocks their slots', () async {
    final (s, svc) = await liveSalon();
    await as('noor@salon.pk');
    final staff = await salons.addStaff(s.id, name: 'Ayesha Malik', email: 'ayesha@salon.pk', phone: '0301 2223334', password: pw, title: 'Senior stylist');
    final b = salons.branches(s.id).single;
    // Two professionals → two free at 10:00.
    expect(bookings.availability(branchId: b.id, serviceIds: [svc.id], day: monday9).first.staffIds, hasLength(2));
    await as('ayesha@salon.pk');
    final l = await salons.requestLeave(from: monday9, to: monday9, reason: 'Family wedding');
    await as('noor@salon.pk');
    await salons.decideLeave(l.id, approve: true);
    expect(bookings.availability(branchId: b.id, serviceIds: [svc.id], day: monday9).first.staffIds, isNot(contains(staff.id)));
  });

  test('chat and complaints reach the other side', () async {
    final (s, _) = await liveSalon();
    await signUp(Role.customer, 'Mariam', 'mariam@example.com');
    final t = await engage.openThread(s.id);
    await engage.send(t.id, 'Do you do keratin?', asSalon: false);
    await engage.raiseComplaint(salonId: s.id, topic: 'Waiting time', text: 'Waited 30 minutes past my time.');
    await as('noor@salon.pk');
    expect(engage.threadsForSalon(s.id).single.id, t.id);
    expect(engage.unread(t.id, asSalon: true), 1);
    await engage.send(t.id, 'Yes, 3 hours, Rs 18,000.', asSalon: true);
    final c = engage.complaintsForSalon(s.id).single;
    await engage.resolveComplaint(c.id, 'Sorry! We have added a second stylist.');
    await as('mariam@example.com');
    expect(engage.unread(t.id, asSalon: false), 1);
    expect(engage.complaintsForCustomer(auth.current!.id).single.status, 'RESOLVED');
  });

  test('trade: credit order → approve → dispatch → deliver → confirm; payment clears credit', () async {
    final (s, _) = await liveSalon();
    final rider = await signUp(Role.rider, 'Usman Ali', 'rider@hola.pk');
    await as('officer@hola.pk');
    final p = await trade.saveProduct(
      name: 'Bond Repair Shampoo', category: 'Care', description: '', color: 0xFF005BAC, shape: '',
      variants: [Variant(id: 'v1', name: '1 L', tradePrice: 2000, retailPrice: 2800, stock: 50)], schemeBuy: 6, schemeFree: 1,
    );
    await trade.setCreditTerms(s.id, limit: 30000, days: 30);
    await as('noor@salon.pk');
    final o = await trade.placeOrder(salonId: s.id, cart: [CartLine(p.id, 'v1', 12)], payment: PaymentMethod.credit);
    expect(o.lines.single.freeQty, 2);
    expect(o.total, 24000);
    expect(o.status, OrderStatus.placed);
    expect(trade.product(p.id)!.variants.single.stock, 36); // 12 + 2 free reserved
    expect(trade.credit(s.id).available, 6000);
    final over = await trade.placeOrder(salonId: s.id, cart: [CartLine(p.id, 'v1', 6)], payment: PaymentMethod.credit);
    expect(over.status, OrderStatus.underReview);
    await trade.cancelOrder(over.id, 'Too much');
    expect(trade.credit(s.id).available, 6000);

    await as('officer@hola.pk');
    await trade.approveOrder(o.id);
    await trade.dispatch(o.id, rider.id);
    await as('rider@hola.pk');
    expect(trade.ordersForRider(rider.id).single.id, o.id);
    await trade.startDelivery(o.id);
    expect(() => trade.deliver(o.id, recipientName: 'Noor', signature: []), throwsA(isA<DomainError>()));
    await trade.deliver(o.id, recipientName: 'Noor', signature: [[(0.1, 0.1), (0.5, 0.6)]]);
    await as('noor@salon.pk');
    await trade.confirmReceipt(o.id);
    expect(trade.order(o.id)!.status, OrderStatus.confirmed);
    await as('officer@hola.pk');
    await trade.recordPayment(s.id, 24000, 'Bank transfer');
    expect(trade.credit(s.id).outstanding, 0);
  });

  test('COD: exact cash required, rider hands over, officer confirms', () async {
    final (s, _) = await liveSalon();
    final rider = await signUp(Role.rider, 'Usman Ali', 'rider@hola.pk');
    await as('officer@hola.pk');
    final p = await trade.saveProduct(name: 'Developer 6%', category: 'Colour', description: '', color: 0xFFFFFFFF, shape: '', variants: [Variant(id: 'v', name: '1 L', tradePrice: 1450, retailPrice: 0, stock: 10)], schemeBuy: 0, schemeFree: 0);
    await as('noor@salon.pk');
    expect(() => trade.placeOrder(salonId: s.id, cart: [CartLine(p.id, 'v', 1)], payment: PaymentMethod.credit), throwsA(isA<DomainError>()));
    final o = await trade.placeOrder(salonId: s.id, cart: [CartLine(p.id, 'v', 2)], payment: PaymentMethod.cod);
    await as('officer@hola.pk');
    await trade.approveOrder(o.id);
    await trade.dispatch(o.id, rider.id);
    await as('rider@hola.pk');
    await trade.startDelivery(o.id);
    expect(() => trade.deliver(o.id, recipientName: 'Noor', signature: [[(0, 0), (1, 1)]], cashCollected: 2000), throwsA(isA<DomainError>()));
    await trade.deliver(o.id, recipientName: 'Noor', signature: [[(0, 0), (1, 1)]], cashCollected: 2900);
    expect(trade.cashOnHand(rider.id), hasLength(1));
    final h = await trade.handOverCash();
    expect(h.amount, 2900);
    expect(trade.cashOnHand(rider.id), isEmpty);
    await as('officer@hola.pk');
    await trade.confirmHandover(h.id);
    expect(trade.handovers().single.status, 'CONFIRMED');
  });

  test('field: plan visit, check in, complete with follow-up, daily report', () async {
    final (s, _) = await liveSalon();
    final v = await field.planVisit(salonId: s.id, at: DateTime(2026, 11, 2, 11), purpose: 'Introduce colour range');
    await field.checkIn(v.id);
    await field.completeVisit(v.id, outcomes: ['INTERESTED'], notes: 'Wants demo', followUpAt: DateTime(2026, 11, 9, 11));
    expect(field.visits(officerId: auth.current!.id), hasLength(2));
    final r = await field.submitReport(notes: 'Good day');
    expect(r.visitsDone, 1);
    expect(() => field.submitReport(notes: ''), throwsA(isA<DomainError>()));
  });

  test('training: officer schedules, staff enrol, seats enforced', () async {
    final (s, _) = await liveSalon();
    final t = await field.saveTraining(title: 'Colour Mastery', description: '', location: 'HOLA Academy', at: DateTime(2026, 11, 5, 11), durationMin: 120, seats: 1);
    await as('noor@salon.pk');
    expect(engage.notifications().any((n) => n.title.startsWith('New training')), isTrue);
    await field.enrol(t.id);
    await salons.addStaff(s.id, name: 'Ayesha', email: 'ayesha@salon.pk', phone: '0301 2223334', password: pw, title: '');
    await as('ayesha@salon.pk');
    expect(() => field.enrol(t.id), throwsA(isA<DomainError>()));
  });

  test('owner manages salon photos; the first is the cover; others cannot change them', () async {
    final (s, _) = await liveSalon();
    await as('noor@salon.pk');
    await salons.setSalonPhotos(s.id, ['a.jpg', 'b.jpg']);
    expect(salons.salon(s.id)!.cover, 'a.jpg');
    await salons.setSalonPhotos(s.id, ['b.jpg', 'a.jpg']);
    expect(salons.salon(s.id)!.cover, 'b.jpg');
    expect(() => salons.setSalonPhotos(s.id, [for (var i = 0; i < maxSalonPhotos + 1; i++) '$i.jpg']), throwsA(isA<DomainError>()));

    // Survives a reload from storage.
    await db.flush();
    final db2 = LocalDatabase(storage);
    await LocalAuthRepository(db2).init();
    expect(LocalSalonRepository(db2).salon(s.id)!.photos, ['b.jpg', 'a.jpg']);

    await signUp(Role.customer, 'Mariam', 'mariam@mail.pk');
    expect(() => salons.setSalonPhotos(s.id, []), throwsA(isA<DomainError>()));
  });
}
