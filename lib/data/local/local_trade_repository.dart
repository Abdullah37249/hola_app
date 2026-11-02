import '../../core/l10n/l10n.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/format.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import 'local_auth_repository.dart';

class LocalTradeRepository extends LocalRepository implements TradeRepository {
  LocalTradeRepository(super.db);

  TradeOrder _order(String id) => order(id) ?? (throw DomainError(tr('Order not found.')));
  Salon _salon(String id) => db.salons.where((s) => s.id == id).firstOrNull ?? (throw DomainError(tr('Salon not found.')));
  NotifLink _link(TradeOrder o) => NotifLink('order', o.id);

  // ── catalogue ──

  @override
  List<Product> products({bool activeOnly = true}) => db.products.where((p) => !activeOnly || p.active).toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Product? product(String id) => db.products.where((p) => p.id == id).firstOrNull;

  @override
  Future<Product> saveProduct({String? id, required String name, required String category, required String description, required int color, required String shape, required List<Variant> variants, required int schemeBuy, required int schemeFree, bool active = true}) async {
    requireRole({Role.salesOfficer});
    if (name.trim().length < 2) throw DomainError(tr('Enter the product name.'));
    if (!productCategories.contains(category)) throw DomainError(tr('Pick a category.'));
    if (variants.isEmpty) throw DomainError(tr('Add at least one size or shade.'));
    for (final v in variants) {
      if (v.name.trim().isEmpty) throw DomainError(tr('Every size or shade needs a name.'));
      if (v.tradePrice <= 0) throw DomainError(tr('Every size or shade needs a trade price.'));
      if (v.stock < 0) throw DomainError(tr("Stock can't be negative."));
    }
    if ((schemeBuy > 0) != (schemeFree > 0)) throw DomainError(tr('A scheme needs both "buy" and "free" quantities.'));
    final existing = id == null ? null : product(id);
    if (existing != null) {
      existing
        ..name = name.trim()
        ..category = category
        ..description = description.trim()
        ..color = color
        ..shape = shape
        ..schemeBuy = schemeBuy
        ..schemeFree = schemeFree
        ..active = active;
      existing.variants
        ..clear()
        ..addAll(variants);
      db.commit();
      return existing;
    }
    final p = Product(id: db.newId(), name: name.trim(), category: category, description: description.trim(), color: color, shape: shape, variants: variants, schemeBuy: schemeBuy, schemeFree: schemeFree, active: active, createdAt: now());
    db.products.add(p);
    db.commit();
    return p;
  }

  @override
  Future<void> restock(String productId, String variantId, int qty) async {
    requireRole({Role.salesOfficer});
    if (qty <= 0) throw DomainError(tr('Enter how many units arrived.'));
    _variant(productId, variantId).stock += qty;
    db.commit();
  }

  Variant _variant(String productId, String variantId) {
    final p = product(productId) ?? (throw DomainError(tr('Product not found.')));
    return p.variants.where((v) => v.id == variantId).firstOrNull ?? (throw DomainError(tr('Size or shade not found.')));
  }

  // ── orders ──

  @override
  List<OrderLine> quote(List<CartLine> cart) => [
        for (final c in cart)
          if (c.qty > 0)
            () {
              final p = product(c.productId)!;
              final v = _variant(c.productId, c.variantId);
              return OrderLine(productId: p.id, variantId: v.id, name: p.variants.length > 1 ? '${p.name} · ${v.name}' : p.name, qty: c.qty, freeQty: p.freeFor(c.qty), unitPrice: v.tradePrice);
            }(),
      ];

  @override
  Future<TradeOrder> placeOrder({required String salonId, required List<CartLine> cart, required PaymentMethod payment, String notes = ''}) async {
    requireRole({Role.salonOwner, Role.salesOfficer});
    final me = requireMe;
    final s = _salon(salonId);
    if (me.role == Role.salonOwner && me.salonId != salonId) throw DomainError(tr('Not your salon.'));
    if (!s.isActive) throw DomainError(tr('Trade ordering opens once HOLA verifies the salon.'));
    final lines = quote(cart);
    if (lines.isEmpty) throw DomainError(tr('Your cart is empty.'));
    for (final l in lines) {
      final v = _variant(l.productId, l.variantId);
      if (l.qty + l.freeQty > v.stock) throw DomainError(tr('Only {n} of {name} in stock.', {'n': v.stock, 'name': l.name}));
    }
    if (payment == PaymentMethod.credit && s.creditLimit <= 0) throw DomainError(tr('This salon has no HOLA credit yet. Choose cash on delivery.'));
    final total = lines.fold(0, (t, l) => t + l.total);
    final overLimit = payment == PaymentMethod.credit && total > credit(salonId).available;
    final o = TradeOrder(
      id: db.newId(),
      code: db.nextOrderCode(),
      salonId: salonId,
      placedById: me.id,
      lines: lines,
      payment: payment,
      notes: notes.trim(),
      status: overLimit ? OrderStatus.underReview : OrderStatus.placed,
      history: [StatusEvent(OrderStatus.placed, now(), me.id), if (overLimit) StatusEvent(OrderStatus.underReview, now(), 'system', 'Over credit limit')],
      createdAt: now(),
    );
    for (final l in lines) {
      _variant(l.productId, l.variantId).stock -= l.qty + l.freeQty; // reserve
    }
    if (payment == PaymentMethod.credit) {
      db.credit.add(CreditEntry(id: db.newId(), salonId: salonId, kind: 'CHARGE', amount: total, ref: o.code, at: now()));
    }
    db.orders.add(o);
    db.notifyRole(Role.salesOfficer, overLimit ? 'Order needs credit review' : 'New trade order', '{salon} · {code} · {amount}', args: {'salon': s.name, 'code': o.code, 'amount': rs(total)}, icon: 'box', link: _link(o));
    if (me.role == Role.salesOfficer) db.notify(s.ownerId, 'Order placed for you', '{code} · {amount} by {name}', args: {'code': o.code, 'amount': rs(total), 'name': me.name}, icon: 'box', link: _link(o));
    db.commit();
    return o;
  }

  @override
  TradeOrder? order(String id) => db.orders.where((o) => o.id == id).firstOrNull;

  @override
  List<TradeOrder> ordersForSalon(String salonId) => db.orders.where((o) => o.salonId == salonId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  List<TradeOrder> allOrders() => [...db.orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  List<TradeOrder> ordersForRider(String riderId) => db.orders.where((o) => o.riderId == riderId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void _move(TradeOrder o, String to, Set<String> from, {String? note}) {
    if (!from.contains(o.status)) throw DomainError(tr('This order is {status}.', {'status': statusLabel(o.status).toLowerCase()}));
    o.status = to;
    o.history.add(StatusEvent(to, now(), requireMe.id, note));
  }

  @override
  Future<void> approveOrder(String id) async {
    requireRole({Role.salesOfficer});
    final o = _order(id);
    _move(o, OrderStatus.approved, {OrderStatus.placed, OrderStatus.underReview});
    db.notify(_salon(o.salonId).ownerId, 'Order approved', '{code} is being packed.', args: {'code': o.code}, icon: 'check', link: _link(o));
    db.commit();
  }

  @override
  Future<void> cancelOrder(String id, String reason) async {
    final o = _order(id);
    final me = requireMe;
    final s = _salon(o.salonId);
    if (me.role == Role.salonOwner) {
      if (me.salonId != o.salonId) throw DomainError(tr('Not your order.'));
      _move(o, OrderStatus.cancelled, {OrderStatus.placed, OrderStatus.underReview}, note: reason);
      db.notifyRole(Role.salesOfficer, 'Order cancelled by salon', '{salon} · {code}', args: {'salon': s.name, 'code': o.code}, icon: 'x', link: _link(o));
    } else {
      requireRole({Role.salesOfficer});
      if (reason.trim().length < 3) throw DomainError(tr('Add the reason for cancelling.'));
      _move(o, OrderStatus.cancelled, {OrderStatus.placed, OrderStatus.underReview, OrderStatus.approved, OrderStatus.dispatched, OrderStatus.failed}, note: reason.trim());
      db.notify(s.ownerId, 'Order cancelled', '{code}: {reason}', args: {'code': o.code, 'reason': reason.trim()}, icon: 'x', link: _link(o));
      if (o.riderId != null) db.notify(o.riderId!, 'Delivery cancelled', '{code} · {salon}', args: {'code': o.code, 'salon': s.name}, icon: 'x', link: _link(o));
    }
    for (final l in o.lines) {
      final v = product(l.productId)?.variants.where((v) => v.id == l.variantId).firstOrNull;
      if (v != null) v.stock += l.qty + l.freeQty; // release reservation
    }
    if (!o.isCod) db.credit.add(CreditEntry(id: db.newId(), salonId: o.salonId, kind: 'REVERSAL', amount: o.total, ref: o.code, note: 'Order cancelled', at: now()));
    db.commit();
  }

  @override
  Future<void> dispatch(String id, String riderId) async {
    requireRole({Role.salesOfficer});
    final o = _order(id);
    final rider = db.accounts.where((a) => a.id == riderId && a.role == Role.rider).firstOrNull ?? (throw DomainError(tr('Pick a rider.')));
    _move(o, OrderStatus.dispatched, {OrderStatus.approved, OrderStatus.failed}, note: rider.name);
    o
      ..riderId = rider.id
      ..failReason = null;
    final s = _salon(o.salonId);
    final b = db.branches.where((b) => b.salonId == s.id).firstOrNull;
    final one = o.units == 1;
    db.notify(
      rider.id,
      'New delivery',
      o.isCod ? (one ? '{place} · {n} unit · collect {amount}' : '{place} · {n} units · collect {amount}') : (one ? '{place} · {n} unit' : '{place} · {n} units'),
      args: {'place': b == null ? s.name : '${s.name}, ${b.area}', 'n': '${o.units}', 'amount': rs(o.total)},
      icon: 'truck',
      link: _link(o),
    );
    db.notify(s.ownerId, 'Order dispatched', '{code} is with {name}.', args: {'code': o.code, 'name': rider.name}, icon: 'truck', link: _link(o));
    db.commit();
  }

  TradeOrder _riderOrder(String id) {
    requireRole({Role.rider});
    final o = _order(id);
    if (o.riderId != requireMe.id) throw DomainError(tr('This delivery is assigned to another rider.'));
    return o;
  }

  @override
  Future<void> startDelivery(String id) async {
    final o = _riderOrder(id);
    _move(o, OrderStatus.outForDelivery, {OrderStatus.dispatched});
    db.notify(_salon(o.salonId).ownerId, 'On the way', '{code} is out for delivery with {name}.', args: {'code': o.code, 'name': requireMe.name}, icon: 'truck', link: _link(o));
    db.commit();
  }

  @override
  Future<void> deliver(String id, {required String recipientName, required Strokes signature, int? cashCollected}) async {
    final o = _riderOrder(id);
    if (recipientName.trim().length < 2) throw DomainError(tr('Enter who received the order.'));
    if (signature.where((s) => s.length > 1).isEmpty) throw DomainError(tr('Ask the recipient to sign.'));
    if (o.isCod && cashCollected != o.total) throw DomainError(tr('Collect exactly {amount} for this cash order.', {'amount': rs(o.total)}));
    _move(o, OrderStatus.delivered, {OrderStatus.outForDelivery});
    o
      ..recipientName = recipientName.trim()
      ..signature = signature
      ..cashCollected = o.isCod ? cashCollected : null;
    db.notify(_salon(o.salonId).ownerId, 'Order delivered', '{code} received by {name}. Please confirm the items.', args: {'code': o.code, 'name': o.recipientName ?? ''}, icon: 'check', link: _link(o));
    db.notifyRole(Role.salesOfficer, 'Delivered', '{salon} · {code}', args: {'salon': _salon(o.salonId).name, 'code': o.code}, icon: 'check', link: _link(o));
    db.commit();
  }

  @override
  Future<void> failDelivery(String id, String reason) async {
    final o = _riderOrder(id);
    if (reason.trim().length < 3) throw DomainError(tr('Say why it could not be delivered.'));
    _move(o, OrderStatus.failed, {OrderStatus.dispatched, OrderStatus.outForDelivery}, note: reason.trim());
    o.failReason = reason.trim();
    final s = _salon(o.salonId);
    db.notify(s.ownerId, 'Delivery attempt failed', '{code}: {reason}', args: {'code': o.code, 'reason': reason.trim()}, icon: 'alert', link: _link(o));
    db.notifyRole(Role.salesOfficer, 'Delivery failed', '{salon} · {code}: {reason}', args: {'salon': s.name, 'code': o.code, 'reason': reason.trim()}, icon: 'alert', link: _link(o));
    db.commit();
  }

  @override
  Future<void> confirmReceipt(String id) async {
    requireRole({Role.salonOwner});
    final o = _order(id);
    if (requireMe.salonId != o.salonId) throw DomainError(tr('Not your order.'));
    _move(o, OrderStatus.confirmed, {OrderStatus.delivered});
    db.commit();
  }

  // ── credit ──

  @override
  CreditSummary credit(String salonId) {
    final s = _salon(salonId);
    final entries = statement(salonId).reversed.toList(); // oldest first
    var credits = entries.where((e) => e.kind != 'CHARGE').fold(0, (t, e) => t + e.amount);
    var outstanding = 0, overdue = 0;
    for (final e in entries.where((e) => e.kind == 'CHARGE')) {
      final paid = credits >= e.amount ? e.amount : credits;
      credits -= paid;
      final left = e.amount - paid;
      outstanding += left;
      if (left > 0 && now().difference(e.at).inDays > s.creditDays) overdue += left;
    }
    final lastPay = entries.lastWhere((e) => e.kind == 'PAYMENT', orElse: () => CreditEntry(id: '', salonId: '', kind: '', amount: 0, ref: '', at: DateTime(0)));
    return CreditSummary(limit: s.creditLimit, outstanding: outstanding, overdue: overdue, days: s.creditDays, lastPayment: lastPay.amount, lastPaymentAt: lastPay.id.isEmpty ? null : lastPay.at);
  }

  @override
  List<CreditEntry> statement(String salonId) => db.credit.where((e) => e.salonId == salonId).toList()..sort((a, b) => b.at.compareTo(a.at));

  @override
  Future<void> setCreditTerms(String salonId, {required int limit, required int days}) async {
    requireRole({Role.salesOfficer});
    final s = _salon(salonId);
    if (limit < 0) throw DomainError(tr("The limit can't be negative."));
    if (days < 1 || days > 120) throw DomainError(tr('Credit days must be between 1 and 120.'));
    s
      ..creditLimit = limit
      ..creditDays = days;
    db.notify(s.ownerId, 'Credit terms updated', 'Limit {amount}, pay within {days} days.', args: {'amount': rs(limit), 'days': '$days'}, icon: 'cash', link: NotifLink('salon', s.id));
    db.commit();
  }

  @override
  Future<void> recordPayment(String salonId, int amount, String note) async {
    requireRole({Role.salesOfficer});
    final s = _salon(salonId);
    if (amount <= 0) throw DomainError(tr('Enter the amount received.'));
    if (amount > credit(salonId).outstanding) throw DomainError(tr('That is more than the salon owes.'));
    db.credit.add(CreditEntry(id: db.newId(), salonId: salonId, kind: 'PAYMENT', amount: amount, ref: 'Payment', note: note.trim(), at: now()));
    db.notify(s.ownerId, 'Payment received', '{amount} recorded by {name}. Thank you!', args: {'amount': rs(amount), 'name': requireMe.name}, icon: 'cash', link: NotifLink('salon', s.id));
    // Orders waiting on credit can now go ahead if they fit.
    db.commit();
  }

  // ── rider cash ──

  @override
  List<TradeOrder> cashOnHand(String riderId) => db.orders
      .where((o) => o.riderId == riderId && o.isCod && o.handoverId == null && (o.status == OrderStatus.delivered || o.status == OrderStatus.confirmed))
      .toList();

  @override
  Future<CashHandover> handOverCash() async {
    requireRole({Role.rider});
    final me = requireMe;
    final os = cashOnHand(me.id);
    if (os.isEmpty) throw DomainError(tr('You have no cash to hand over.'));
    final h = CashHandover(id: db.newId(), riderId: me.id, orderIds: [for (final o in os) o.id], amount: os.fold(0, (t, o) => t + (o.cashCollected ?? 0)), at: now());
    for (final o in os) {
      o.handoverId = h.id;
    }
    db.handovers.add(h);
    db.notifyRole(Role.salesOfficer, 'Cash handed over', os.length == 1 ? '{name} · {amount} for {n} delivery. Please confirm.' : '{name} · {amount} for {n} deliveries. Please confirm.', args: {'name': me.name, 'amount': rs(h.amount), 'n': '${os.length}'}, icon: 'cash');
    db.commit();
    return h;
  }

  @override
  List<CashHandover> handovers({String? riderId}) => db.handovers.where((h) => riderId == null || h.riderId == riderId).toList()..sort((a, b) => b.at.compareTo(a.at));

  @override
  Future<void> confirmHandover(String id) async {
    requireRole({Role.salesOfficer});
    final h = db.handovers.where((x) => x.id == id).firstOrNull ?? (throw DomainError(tr('Handover not found.')));
    if (h.status == 'CONFIRMED') throw DomainError(tr('Already confirmed.'));
    h
      ..status = 'CONFIRMED'
      ..confirmedById = requireMe.id
      ..confirmedAt = now();
    db.notify(h.riderId, 'Cash received', '{amount} confirmed by {name}.', args: {'amount': rs(h.amount), 'name': requireMe.name}, icon: 'check');
    db.commit();
  }
}
