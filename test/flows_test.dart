import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/core/security/sha256.dart';
import 'package:hola_professional/core/utils/clock.dart';
import 'package:hola_professional/data/local/local_auth_repository.dart';
import 'package:hola_professional/data/local/local_booking_repository.dart';
import 'package:hola_professional/data/local/local_database.dart';
import 'package:hola_professional/data/local/local_engagement_repository.dart';
import 'package:hola_professional/data/local/local_chat_repository.dart';
import 'package:hola_professional/data/local/local_field_repository.dart';
import 'package:hola_professional/data/local/local_salon_repository.dart';
import 'package:hola_professional/data/local/local_trade_repository.dart';
import 'package:hola_professional/data/local/local_return_repository.dart';
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
  late LocalChatRepository chat;
  late LocalTradeRepository trade;
  late LocalFieldRepository field;
  late LocalReturnRepository returns;
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
    chat = LocalChatRepository(db);
    trade = LocalTradeRepository(db);
    field = LocalFieldRepository(db);
    returns = LocalReturnRepository(db);
    await auth.init();
  });

  // Officers and riders come from HOLA: create them, then sign in like the app does.
  Future<Account> signUp(Role r, String name, String email) async {
    if (Role.signUp.contains(r)) return auth.signUp(role: r, name: name, email: email, phone: '0300 1234567', password: pw);
    final a = await auth.provision(role: r, name: name, email: email, phone: '0300 1234567', password: pw);
    await auth.signIn(email, pw);
    return a;
  }

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

  test('a review waiting for HOLA: the salon sees it, clients and the rating do not', () async {
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
    final r = await engage.addReview(appointmentId: a.id, stars: 1, text: 'Burnt');
    r.pending = true; // as HOLA holds it until staff publish it
    expect(engage.reviewsForSalon(s.id), isEmpty);
    expect(engage.reviewsForSalon(s.id, withPending: true).single.id, r.id);
    expect(salons.rating(s.id).count, 0);
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

  test('sign-up is for customers and salons; officers and riders only sign in', () async {
    for (final r in [Role.salesOfficer, Role.rider, Role.salonStaff]) {
      expect(() => auth.signUp(role: r, name: 'Someone', email: '${r.name}@x.pk', phone: '0300 1234567', password: pw), throwsA(isA<DomainError>()));
    }
    await auth.provision(role: Role.rider, name: 'Usman Ali', email: 'rider@hola.pk', phone: '0300 1234567', password: pw);
    expect(auth.current, isNull); // HOLA creates it; the rider then signs in
    await auth.signIn('rider@hola.pk', pw);
    expect(auth.current!.role, Role.rider);
    expect(Role.signUp, [Role.customer, Role.salonOwner]);
  });

  test('team: added by the salon without a login; salon adds time off that blocks their slots', () async {
    final (s, svc) = await liveSalon();
    await as('noor@salon.pk');
    final staff = await salons.addStaff(s.id, name: 'Ayesha Malik', phone: '0301 2223334', title: 'Senior stylist');
    expect(staff.email, isEmpty);
    final b = salons.branches(s.id).single;
    // Two professionals → two free at 10:00.
    expect(bookings.availability(branchId: b.id, serviceIds: [svc.id], day: monday9).first.staffIds, hasLength(2));
    final l = await salons.requestLeave(staffId: staff.id, from: monday9, to: monday9, reason: 'Family wedding');
    expect(l.status, 'APPROVED');
    expect(bookings.availability(branchId: b.id, serviceIds: [svc.id], day: monday9).first.staffIds, isNot(contains(staff.id)));
    await salons.cancelLeave(l.id);
    expect(bookings.availability(branchId: b.id, serviceIds: [svc.id], day: monday9).first.staffIds, contains(staff.id));
    // Nobody can sign in as a team member, not even with an empty email.
    await auth.signOut();
    expect(() => auth.signIn('', ''), throwsA(isA<DomainError>()));
  });

  test('chat and complaints reach the other side', () async {
    final (s, _) = await liveSalon();
    await signUp(Role.customer, 'Mariam', 'mariam@example.com');
    final t = await chat.open(salonId: s.id);
    await chat.send(t.id, text: 'Do you do keratin?');
    await engage.raiseComplaint(salonId: s.id, topic: 'Waiting time', text: 'Waited 30 minutes past my time.');
    await as('noor@salon.pk');
    expect(chat.threads().single.id, t.id);
    expect(chat.unread(t.id), 1);
    await chat.send(t.id, text: 'Yes, 3 hours, Rs 18,000.');
    final c = engage.complaintsForSalon(s.id).single;
    await engage.resolveComplaint(c.id, 'Sorry! We have added a second stylist.');
    await as('mariam@example.com');
    expect(chat.unread(t.id), 1);
    await chat.markRead(t.id);
    expect(chat.unreadTotal, 0);
    expect(engage.complaintsForCustomer(auth.current!.id).single.status, 'RESOLVED');
  });

  test('trade: credit order → approve → dispatch → deliver → confirm; payment clears credit', () async {
    final (s, _) = await liveSalon();
    final rider = await signUp(Role.rider, 'Usman Ali', 'rider@hola.pk');
    await as('officer@hola.pk');
    final p = await trade.saveProduct(
      name: 'Bond Repair Shampoo',
      category: 'Care',
      description: '',
      color: 0xFF005BAC,
      shape: '',
      variants: [Variant(id: 'v1', name: '1 L', tradePrice: 2000, retailPrice: 2800, stock: 50)],
      schemeBuy: 6,
      schemeFree: 1,
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
    await trade.deliver(
      o.id,
      recipientName: 'Noor',
      signature: [
        [(0.1, 0.1), (0.5, 0.6)],
      ],
    );
    await as('noor@salon.pk');
    await trade.confirmReceipt(o.id);
    expect(trade.order(o.id)!.status, OrderStatus.confirmed);
    await as('officer@hola.pk');
    await trade.recordPayment(s.id, 24000, 'Bank transfer');
    expect(trade.credit(s.id).outstanding, 0);
  });

  /// A delivered order of 10 (+ any free) units at Rs 1000, paid by [payment]. Returns (salon, order, rider).
  Future<(Salon, TradeOrder, Account)> deliveredOrder(PaymentMethod payment, {int buy = 0, int free = 0}) async {
    final (s, _) = await liveSalon();
    final rider = await signUp(Role.rider, 'Usman Ali', 'rider@hola.pk');
    await as('officer@hola.pk');
    final p = await trade.saveProduct(
      name: 'Colour Shampoo',
      category: 'Care',
      description: '',
      color: 0xFF005BAC,
      shape: '',
      variants: [Variant(id: 'v1', name: '1 L', tradePrice: 1000, retailPrice: 1400, stock: 50)],
      schemeBuy: buy,
      schemeFree: free,
    );
    await trade.setCreditTerms(s.id, limit: 50000, days: 30);
    await as('noor@salon.pk');
    final o = await trade.placeOrder(salonId: s.id, cart: [CartLine(p.id, 'v1', 10)], payment: payment);
    await as('officer@hola.pk');
    await trade.approveOrder(o.id);
    await trade.dispatch(o.id, rider.id);
    await as('rider@hola.pk');
    await trade.startDelivery(o.id);
    await trade.deliver(
      o.id,
      recipientName: 'Noor',
      signature: [
        [(0, 0), (1, 1)],
      ],
      cashCollected: payment == PaymentMethod.cod ? o.total : null,
    );
    return (s, trade.order(o.id)!, rider);
  }

  test('returns: credit order → approve → rider collects → outstanding goes down, once', () async {
    final (s, o, rider) = await deliveredOrder(PaymentMethod.credit);
    await as('noor@salon.pk');
    final owed = trade.credit(s.id).outstanding;
    expect(owed, 10000);
    // Rules: something picked, a reason, no more than was delivered.
    expect(() => returns.requestReturn(orderId: o.id, option: ReturnOption.refund, reason: ReturnReason.expired, qty: {}), throwsA(isA<DomainError>()));
    expect(() => returns.requestReturn(orderId: o.id, option: ReturnOption.refund, reason: ReturnReason.other, qty: {'v1': 1}), throwsA(isA<DomainError>()));
    expect(() => returns.requestReturn(orderId: o.id, option: ReturnOption.refund, reason: ReturnReason.expired, qty: {'v1': 11}), throwsA(isA<DomainError>()));
    final r = await returns.requestReturn(orderId: o.id, option: ReturnOption.refund, reason: ReturnReason.expired, note: 'Expired in October', qty: {'v1': 3});
    expect(r.amount, 3000);
    expect(r.adjustsOutstanding, isTrue);
    expect(r.status, ReturnStatus.requested);
    // Its conversation with HOLA starts with the reason.
    final t = chat.thread(r.conversationId!)!;
    expect(t.withHola, isTrue);
    expect(chat.messages(t.id).single.text, contains('Expired in October'));
    // No duplicates: only the 7 units left can go into another request.
    expect(returns.returnable(o, 'v1'), 7);
    expect(() => returns.requestReturn(orderId: o.id, option: ReturnOption.replace, reason: ReturnReason.damaged, qty: {'v1': 8}), throwsA(isA<DomainError>()));

    await as('officer@hola.pk');
    expect(chat.threads().map((x) => x.id), contains(t.id)); // HOLA's team sees it
    await returns.startReview(r.id);
    await returns.approveReturn(r.id);
    // Approved is not enough: nothing moves until the rider has the goods.
    expect(trade.credit(s.id).outstanding, owed);
    expect(() => returns.cancelReturn(r.id), throwsA(isA<DomainError>()));
    await returns.assignPickup(r.id, rider.id);
    await as('rider@hola.pk');
    expect(returns.pickups().single.units, 3);
    await returns.collectPickup(r.id);
    expect(returns.returnRequest(r.id)!.status, ReturnStatus.completed);
    expect(returns.returnRequest(r.id)!.settlement!.type, SettlementType.creditAdjusted);
    await as('noor@salon.pk');
    expect(trade.credit(s.id).outstanding, owed - 3000);
    expect(engage.notifications().map((n) => n.title), contains('Outstanding adjusted'));
    // The audit trail has every step.
    expect(returns.returnRequest(r.id)!.history.map((h) => h.status), [ReturnStatus.requested, ReturnStatus.underReview, ReturnStatus.approved, ReturnStatus.pickupAssigned, ReturnStatus.completed]);
  });

  test('returns: a cash order gets an offer; the voucher exists only after the salon accepts and the rider collects', () async {
    final (_, o, rider) = await deliveredOrder(PaymentMethod.cod);
    await as('noor@salon.pk');
    final r = await returns.requestReturn(orderId: o.id, option: ReturnOption.refund, reason: ReturnReason.damaged, qty: {'v1': 2});
    expect(r.adjustsOutstanding, isFalse);
    await as('officer@hola.pk');
    // A cash refund isn't approved straight away: HOLA makes an offer.
    expect(() => returns.approveReturn(r.id), throwsA(isA<DomainError>()));
    await returns.proposeSettlement(r.id, settlement: Settlement.voucher, note: 'Voucher for next order');
    expect(returns.returnRequest(r.id)!.status, ReturnStatus.awaitingSalon);
    expect(returns.returnRequest(r.id)!.settlement, isNull);
    await as('noor@salon.pk');
    await returns.declineProposal(r.id, 'I prefer new bottles');
    expect(returns.returnRequest(r.id)!.status, ReturnStatus.underReview);
    await as('officer@hola.pk');
    await returns.proposeSettlement(r.id, settlement: Settlement.voucher);
    await as('noor@salon.pk');
    await returns.acceptProposal(r.id);
    expect(returns.returnRequest(r.id)!.status, ReturnStatus.approved);
    expect(returns.returnRequest(r.id)!.settlement, isNull); // no voucher yet
    await as('officer@hola.pk');
    await returns.assignPickup(r.id, rider.id);
    await as('rider@hola.pk');
    await returns.collectPickup(r.id);
    final done = returns.returnRequest(r.id)!;
    expect(done.status, ReturnStatus.completed);
    expect(done.settlement!.voucher!.amount, 2000);
    expect(done.settlement!.voucher!.code, startsWith('HV-'));
  });

  test('returns: a replacement order goes through the normal flow and ends the return', () async {
    final (s, o, rider) = await deliveredOrder(PaymentMethod.credit, buy: 5, free: 1);
    await as('noor@salon.pk');
    // 10 bought + 2 free: 12 units, worth Rs 10000 → Rs 833 each.
    expect(returns.returnable(o, 'v1'), 12);
    expect(returns.unitValue(o, 'v1'), 833);
    final owed = trade.credit(s.id).outstanding;
    final r = await returns.requestReturn(orderId: o.id, option: ReturnOption.replace, reason: ReturnReason.wrongItem, qty: {'v1': 1});
    await as('officer@hola.pk');
    await returns.approveReturn(r.id);
    await returns.assignPickup(r.id, rider.id);
    await as('rider@hola.pk');
    await returns.collectPickup(r.id);
    final x = returns.returnRequest(r.id)!;
    expect(x.status, ReturnStatus.replacementCreated);
    final repl = trade.order(x.settlement!.replacementOrderId!)!;
    expect(repl.total, 0);
    expect(repl.replacementFor, r.code);
    expect(repl.status, OrderStatus.approved);
    expect(trade.credit(s.id).outstanding, owed); // free of charge
    await as('officer@hola.pk');
    await trade.dispatch(repl.id, rider.id);
    await as('rider@hola.pk');
    await trade.startDelivery(repl.id);
    await trade.deliver(
      repl.id,
      recipientName: 'Noor',
      signature: [
        [(0, 0), (1, 1)],
      ],
    );
    await as('noor@salon.pk');
    await returns.syncReturns();
    expect(returns.returnRequest(r.id)!.status, ReturnStatus.completed);
  });

  test('returns: only a delivered order can be returned', () async {
    final (s, _) = await liveSalon();
    await as('officer@hola.pk');
    final p = await trade.saveProduct(
      name: 'Toner',
      category: 'Colour',
      description: '',
      color: 0xFFFFFFFF,
      shape: '',
      variants: [Variant(id: 'v', name: '1 L', tradePrice: 500, retailPrice: 0, stock: 10)],
      schemeBuy: 0,
      schemeFree: 0,
    );
    await as('noor@salon.pk');
    final pending = await trade.placeOrder(salonId: s.id, cart: [CartLine(p.id, 'v', 2)], payment: PaymentMethod.cod);
    expect(returns.canReturn(pending), isFalse);
    expect(() => returns.requestReturn(orderId: pending.id, option: ReturnOption.replace, reason: ReturnReason.damaged, qty: {'v': 1}), throwsA(isA<DomainError>()));
  });

  test('HOLA chat: the salon shares an order as a card; customer chats can\'t carry cards', () async {
    final (s, o, _) = await deliveredOrder(PaymentMethod.credit);
    await as('noor@salon.pk');
    final t = await chat.openHola(salonId: s.id);
    await chat.send(
      t.id,
      ref: MsgRef(type: MsgRef.order, id: o.id, code: o.code, title: 'Order', status: o.status, amount: o.total),
    );
    final m = chat.messages(t.id).single;
    expect(m.text, isEmpty);
    expect(m.ref!.code, o.code);
    await as('officer@hola.pk');
    expect(chat.unread(t.id), 1); // HOLA's team got it
    await signUp(Role.customer, 'Mariam', 'mariam@example.com');
    final c = await chat.open(salonId: s.id);
    expect(
      () => chat.send(
        c.id,
        ref: MsgRef(type: MsgRef.order, id: o.id),
      ),
      throwsA(isA<DomainError>()),
    );
  });

  test('returns: withdraw and reject free the units again', () async {
    final (_, o, _) = await deliveredOrder(PaymentMethod.credit);
    await as('noor@salon.pk');
    final a = await returns.requestReturn(orderId: o.id, option: ReturnOption.replace, reason: ReturnReason.damaged, qty: {'v1': 10});
    expect(returns.canReturn(o), isFalse);
    await returns.cancelReturn(a.id);
    expect(returns.returnable(o, 'v1'), 10);
    final b = await returns.requestReturn(orderId: o.id, option: ReturnOption.replace, reason: ReturnReason.damaged, qty: {'v1': 4});
    await as('officer@hola.pk');
    expect(() => returns.rejectReturn(b.id, ''), throwsA(isA<DomainError>()));
    await returns.rejectReturn(b.id, 'Damage happened after delivery');
    await as('noor@salon.pk');
    expect(returns.returnRequest(b.id)!.status, ReturnStatus.rejected);
    expect(returns.returnable(o, 'v1'), 10);
  });

  test('reviews: the salon deletes a review on its profile; the rating follows; no second review', () async {
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
    final r = await engage.addReview(appointmentId: a.id, stars: 1, text: 'Not happy');
    // Published straight away: on the profile and in the rating.
    expect(engage.reviewsForSalon(s.id).single.id, r.id);
    expect(() => engage.deleteReview(r.id), throwsA(isA<DomainError>())); // not the customer's to delete
    await as('noor@salon.pk');
    await engage.replyToReview(r.id, 'Sorry, please come back and we will fix it.');
    expect(engage.reviewsForSalon(s.id).single.reply, isNotNull);
    await engage.deleteReview(r.id);
    expect(engage.reviewsForSalon(s.id, withPending: true), isEmpty);
    expect(salons.rating(s.id).count, 0);
    await as('mariam@example.com');
    expect(() => engage.addReview(appointmentId: a.id, stars: 5, text: ''), throwsA(isA<DomainError>()));
  });

  test('product reviews: the salon rates products it received, once each; HOLA can delete them', () async {
    final (s, o, _) = await deliveredOrder(PaymentMethod.credit);
    await as('noor@salon.pk');
    expect(trade.canRateProducts(o), isTrue);
    expect(() => trade.rateProducts(o.id, {'v1': (0, '')}), throwsA(isA<DomainError>()));
    expect(() => trade.rateProducts(o.id, {'v1': (6, '')}), throwsA(isA<DomainError>()));
    await trade.rateProducts(o.id, {'v1': (4, 'Good lather')});
    expect(trade.productReviewsOn(o.id)['v1']!.rating, 4);
    expect(trade.canRateProducts(o), isFalse); // every product rated
    expect(() => trade.rateProducts(o.id, {'v1': (5, '')}), throwsA(isA<DomainError>()));
    final pid = o.lines.single.productId;
    expect(trade.productRating(pid), (4.0, 1));
    // Not the salon's to delete; HOLA's team can.
    expect(() => trade.deleteProductReview(trade.allProductReviews().single.id), throwsA(isA<DomainError>()));
    await as('officer@hola.pk');
    await trade.deleteProductReview(trade.allProductReviews().single.id);
    expect(trade.productRating(pid), (0.0, 0));
    expect(s.id, isNotEmpty);
  });

  test('product reviews: not before delivery', () async {
    final (s, _) = await liveSalon();
    await as('officer@hola.pk');
    final p = await trade.saveProduct(
      name: 'Toner',
      category: 'Colour',
      description: '',
      color: 0xFFFFFFFF,
      shape: '',
      variants: [Variant(id: 'v', name: '1 L', tradePrice: 500, retailPrice: 0, stock: 10)],
      schemeBuy: 0,
      schemeFree: 0,
    );
    await as('noor@salon.pk');
    final o = await trade.placeOrder(salonId: s.id, cart: [CartLine(p.id, 'v', 1)], payment: PaymentMethod.cod);
    expect(trade.canRateProducts(o), isFalse);
    expect(() => trade.rateProducts(o.id, {'v': (5, '')}), throwsA(isA<DomainError>()));
  });

  test('COD: exact cash required, rider hands over, officer confirms', () async {
    final (s, _) = await liveSalon();
    final rider = await signUp(Role.rider, 'Usman Ali', 'rider@hola.pk');
    await as('officer@hola.pk');
    final p = await trade.saveProduct(
      name: 'Developer 6%',
      category: 'Colour',
      description: '',
      color: 0xFFFFFFFF,
      shape: '',
      variants: [Variant(id: 'v', name: '1 L', tradePrice: 1450, retailPrice: 0, stock: 10)],
      schemeBuy: 0,
      schemeFree: 0,
    );
    await as('noor@salon.pk');
    expect(() => trade.placeOrder(salonId: s.id, cart: [CartLine(p.id, 'v', 1)], payment: PaymentMethod.credit), throwsA(isA<DomainError>()));
    final o = await trade.placeOrder(salonId: s.id, cart: [CartLine(p.id, 'v', 2)], payment: PaymentMethod.cod);
    await as('officer@hola.pk');
    await trade.approveOrder(o.id);
    await trade.dispatch(o.id, rider.id);
    await as('rider@hola.pk');
    await trade.startDelivery(o.id);
    expect(
      () => trade.deliver(
        o.id,
        recipientName: 'Noor',
        signature: [
          [(0, 0), (1, 1)],
        ],
        cashCollected: 2000,
      ),
      throwsA(isA<DomainError>()),
    );
    await trade.deliver(
      o.id,
      recipientName: 'Noor',
      signature: [
        [(0, 0), (1, 1)],
      ],
      cashCollected: 2900,
    );
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

  test('training: salon enrols itself and its team, seats enforced, attendance gives certificates', () async {
    final (s, _) = await liveSalon();
    final officer = auth.current!.id;
    final t = await field.saveTraining(title: 'Colour Mastery', description: '', location: 'HOLA Academy', at: DateTime(2026, 11, 5, 11), durationMin: 120, seats: 2);
    await as('noor@salon.pk');
    final owner = auth.current!.id;
    expect(engage.notifications().any((n) => n.title.startsWith('New training')), isTrue);
    final ayesha = await salons.addStaff(s.id, name: 'Ayesha Malik', title: '');
    final hamza = await salons.addStaff(s.id, name: 'Hamza Iqbal', title: '');
    await field.enrol(t.id);
    await field.enrol(t.id, personId: ayesha.id);
    expect(field.training(t.id)!.enrolled, [owner, ayesha.id]);
    expect(() => field.enrol(t.id, personId: hamza.id), throwsA(isA<DomainError>())); // full
    await field.withdraw(t.id, personId: ayesha.id);
    await field.enrol(t.id, personId: hamza.id);
    // Another salon can't enrol someone else's team.
    await signUp(Role.salonOwner, 'Rabia', 'rabia@salon.pk');
    expect(() => field.enrol(t.id, personId: ayesha.id), throwsA(isA<DomainError>()));
    await as('officer@hola.pk');
    expect(auth.current!.id, officer);
    clock = () => DateTime(2026, 11, 5, 14);
    await field.completeTraining(t.id, [owner, hamza.id]);
    await as('noor@salon.pk');
    // One notice for the salon covers the team member who attended.
    expect(engage.notifications().where((n) => n.title == 'Training completed'), hasLength(2));
    expect(engage.notifications().any((n) => n.args['names'] == 'Hamza'), isTrue);
    expect(field.training(t.id)!.attended, [owner, hamza.id]);
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

  test('salon offers: discount at booking, once per customer, freed on cancel, spent on completion, ends on time', () async {
    final (s, svc) = await liveSalon(); // Rs 3500 haircut
    final b = salons.branches(s.id).single;
    await as('noor@salon.pk');
    // Rules: 1–90%, an amount below the price, no end in the past, one offer per service at a time.
    expect(
      () => salons.saveOffer(salonId: s.id, serviceId: svc.id, discountType: DiscountType.percent, discountValue: 95, startDay: monday9, lastDay: monday9, active: true),
      throwsA(isA<DomainError>()),
    );
    expect(
      () => salons.saveOffer(salonId: s.id, serviceId: svc.id, discountType: DiscountType.amount, discountValue: 3500, startDay: monday9, lastDay: monday9, active: true),
      throwsA(isA<DomainError>()),
    );
    // A rupee discount is capped at 90% of the price too (Rs 3150 of Rs 3500).
    expect(maxOfferAmount(3500), 3150);
    expect(
      () => salons.saveOffer(salonId: s.id, serviceId: svc.id, discountType: DiscountType.amount, discountValue: 3151, startDay: monday9, lastDay: monday9, active: true),
      throwsA(isA<DomainError>()),
    );
    expect(
      () => salons.saveOffer(salonId: s.id, serviceId: svc.id, discountType: DiscountType.percent, discountValue: 20, startDay: DateTime(2026, 10, 1), lastDay: DateTime(2026, 11, 1), active: true),
      throwsA(isA<DomainError>()),
    );
    final o = await salons.saveOffer(salonId: s.id, serviceId: svc.id, discountType: DiscountType.percent, discountValue: 20, startDay: monday9, lastDay: DateTime(2026, 11, 6), active: true);
    expect(
      () => salons.saveOffer(salonId: s.id, serviceId: svc.id, discountType: DiscountType.amount, discountValue: 500, startDay: DateTime(2026, 11, 5), lastDay: DateTime(2026, 11, 9), active: true),
      throwsA(isA<DomainError>()),
    );

    // Every customer who can see the salon sees the offer.
    await signUp(Role.customer, 'Mariam', 'mariam@example.com');
    expect(salons.liveOffers().single.id, o.id);
    expect(salons.offerFor(svc.id)?.id, o.id);
    final a = await bookings.book(salonId: s.id, branchId: b.id, serviceIds: [svc.id], start: DateTime(2026, 11, 2, 10));
    expect(a.price, 2800);
    expect(a.discount, 700);
    expect(salons.offerUse(o), OfferUse.reserved);
    expect(salons.heldOn(o), a.code);
    // Held: a second booking pays full price.
    final a2 = await bookings.book(salonId: s.id, branchId: b.id, serviceIds: [svc.id], start: DateTime(2026, 11, 3, 10));
    expect(a2.price, 3500);
    await bookings.cancel(a2.id, 'Plans changed');
    // Cancelling the booking that holds it frees it again.
    await bookings.cancel(a.id, 'Plans changed');
    expect(salons.offerUse(o), OfferUse.none);
    expect(salons.liveOffers().single.id, o.id); // back in their offers
    final a3 = await bookings.book(salonId: s.id, branchId: b.id, serviceIds: [svc.id], start: DateTime(2026, 11, 2, 11));
    expect(a3.price, 2800);

    // Another customer has their own use.
    await signUp(Role.customer, 'Sana', 'sana@example.com');
    expect(salons.offerUse(o), OfferUse.none);

    // Completed: spent for good.
    await as('noor@salon.pk');
    await bookings.confirm(a3.id);
    clock = () => DateTime(2026, 11, 2, 10, 55);
    await bookings.checkIn(a3.id);
    await bookings.startService(a3.id);
    await bookings.complete(a3.id);
    expect(salons.offerStats(o), (used: 1, held: 0));
    await as('mariam@example.com');
    expect(salons.offerUse(o), OfferUse.used);
    expect(salons.offerFor(svc.id), isNull);
    expect(salons.liveOffers(), isEmpty); // gone from this customer's offers
    final a4 = await bookings.book(salonId: s.id, branchId: b.id, serviceIds: [svc.id], start: DateTime(2026, 11, 4, 10));
    expect(a4.price, 3500);

    // Switched off, then ended: nobody gets it.
    await as('sana@example.com');
    expect(salons.offerFor(svc.id)?.id, o.id);
    await as('noor@salon.pk');
    await salons.setOfferActive(o.id, false);
    await as('sana@example.com');
    expect(salons.liveOffers(), isEmpty);
    await as('noor@salon.pk');
    await salons.setOfferActive(o.id, true);
    clock = () => DateTime(2026, 11, 7, 9);
    await as('sana@example.com');
    expect(salons.liveOffers(), isEmpty);
    expect(o.statusAt(DateTime(2026, 11, 7, 9)), 'EXPIRED');
    final a5 = await bookings.book(salonId: s.id, branchId: b.id, serviceIds: [svc.id], start: DateTime(2026, 11, 9, 10));
    expect(a5.price, 3500);
  });

  test('branches: a new one copies the hours; team members book only where they work; deleting moves them back', () async {
    final (s, svc) = await liveSalon();
    await as('noor@salon.pk');
    final main = salons.branches(s.id).single;
    expect(() => salons.addBranch(s.id, name: main.name, address: '1 Road', area: '', city: 'Lahore'), throwsA(isA<DomainError>()));
    final dha = await salons.addBranch(s.id, name: 'DHA Phase 6', address: '5 Main St', area: 'DHA', city: 'Lahore');
    expect(dha.hours, main.hours);
    final owner = salons.staff(s.id).single;
    // The owner works at the main branch: the new branch has no free times yet.
    expect(bookings.availability(branchId: dha.id, serviceIds: [svc.id], day: monday9), isEmpty);
    await salons.updateStaff(owner.accountId, title: 'Owner', bookable: true, week: owner.week, branchId: dha.id);
    expect(bookings.availability(branchId: dha.id, serviceIds: [svc.id], day: monday9), isNotEmpty);
    expect(bookings.availability(branchId: main.id, serviceIds: [svc.id], day: monday9), isEmpty);
    await salons.deleteBranch(dha.id);
    expect(salons.branches(s.id).single.id, main.id);
    expect(salons.staffProfile(owner.accountId)!.branchId, isNull);
    expect(bookings.availability(branchId: main.id, serviceIds: [svc.id], day: monday9), isNotEmpty);
    expect(() => salons.deleteBranch(main.id), throwsA(isA<DomainError>())); // a salon keeps one branch
  });
}
