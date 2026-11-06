import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/format.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/repositories.dart';
import 'hola_mirror.dart' show branchGeo, money, mirrorPerson;
import 'local_auth_repository.dart';

class LocalTradeRepository extends LocalRepository implements TradeRepository {
  LocalTradeRepository(super.db, {this.api}) {
    db.onWipe(() {
      _serverCredit.clear();
      _payRequests.clear();
      _serverStatement.clear();
      _ratings.clear();
      _coupons.clear();
      _collections = const [];
      _creditCollections.clear();
      _serverCash = null;
    });
  }

  /// The HOLA server; null keeps everything on the device (widget tests).
  final HolaApi? api;
  Future<void>? _syncing;

  /// The salon's HOLA credit account as the server reports it.
  final _serverCredit = <String, CreditSummary>{};

  /// The salon's payment requests as the server reports them (newest first).
  final _payRequests = <String, List<PaymentRequest>>{};

  /// The salon's credit statement as the server reports it (newest first).
  final _serverStatement = <String, List<CreditEntry>>{};

  TradeOrder _order(String id) => order(id) ?? (throw DomainError(tr('Order not found.')));
  Salon _salon(String id) => db.salons.where((s) => s.id == id).firstOrNull ?? (throw DomainError(tr('Salon not found.')));
  NotifLink _link(TradeOrder o) => NotifLink('order', o.id);

  // ── catalogue ──

  /// Officer tools that change orders, money, stock or products work only on
  /// the phone's own data. With HOLA connected, HOLA staff do these in the
  /// HOLA dashboard, where the server checks permissions; faking them here
  /// would show changes HOLA never made.
  @override
  bool get officerToolsOnPhone => api == null;

  void _phoneOnly() {
    if (!officerToolsOnPhone) throw DomainError(tr('HOLA handles this in the HOLA dashboard.'));
  }

  @override
  Future<void> syncCatalogue() => api == null ? Future.value() : (_syncing ??= _syncCatalogue().whenComplete(() => _syncing = null));

  /// Copies GET /catalog/trade into the device database. Signed-in salon only.
  Future<void> _syncCatalogue() async {
    if (me?.role != Role.salonOwner || !await api!.hasSession) return;
    try {
      final res = await api!.get('/catalog/trade');
      final items = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<Map>();
      final seen = <String>{};
      for (final (i, j) in items.indexed) {
        final p = mirrorProduct(j, i);
        seen.add(p.id);
        // Salons' ratings of the product (contract 0.24.0).
        if (j['rating'] case final Map r when asIntOr(r['count']) > 0) _ratings[p.id] = (double.tryParse('${r['average']}') ?? 0, asIntOr(r['count']));
        final at = db.products.indexWhere((x) => x.id == p.id);
        at < 0 ? db.products.add(p) : db.products[at] = p;
      }
      // Products HOLA no longer sells leave the catalogue.
      db.products.removeWhere((p) => p.hola && !seen.contains(p.id));
      db.commit();
    } catch (_) {
      // Offline or not allowed: keep the last catalogue.
    }
  }

  @override
  List<Product> products({bool activeOnly = true}) {
    // Once HOLA's server catalogue has arrived, it is the only catalogue.
    final fromHola = db.products.any((p) => p.hola);
    return db.products.where((p) => (!activeOnly || p.active) && (!fromHola || p.hola)).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Product? product(String id) => db.products.where((p) => p.id == id).firstOrNull;

  @override
  Future<Product> saveProduct({
    String? id,
    required String name,
    required String category,
    required String description,
    required int color,
    required String shape,
    required List<Variant> variants,
    required int schemeBuy,
    required int schemeFree,
    bool active = true,
  }) async {
    requireRole({Role.salesOfficer});
    _phoneOnly();
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
    final p = Product(
      id: db.newId(),
      name: name.trim(),
      category: category,
      description: description.trim(),
      color: color,
      shape: shape,
      variants: variants,
      schemeBuy: schemeBuy,
      schemeFree: schemeFree,
      active: active,
      createdAt: now(),
    );
    db.products.add(p);
    db.commit();
    return p;
  }

  @override
  Future<void> restock(String productId, String variantId, int qty) async {
    requireRole({Role.salesOfficer});
    _phoneOnly();
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
  Future<OrderQuote> quoteWithCoupon({required String salonId, required List<CartLine> cart, required String couponCode}) async {
    final code = couponCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9-]{4,24}$').hasMatch(code)) throw DomainError(tr('Enter the coupon code as it is written (4–24 letters or numbers).'), field: 'couponCode');
    final lines = quote(cart);
    if (lines.isEmpty) throw DomainError(tr('Your cart is empty.'));
    if (api == null || !lines.every((l) => product(l.productId)?.hola ?? false)) throw DomainError(tr('Coupons work on HOLA products only.'), field: 'couponCode');
    // HOLA's list already says this salon used it, or it's held by an order.
    final mine = coupons(salonId).where((c) => c.code.toUpperCase() == code).firstOrNull;
    if (mine != null && mine.used) throw DomainError(tr('You have already used this coupon.'), field: 'couponCode');
    if (mine != null && mine.reserved) throw _reserved(mine.reservedOnOrder);
    try {
      final j =
          await api!.post('/salons/$salonId/orders/quote', {
                'items': [
                  for (final l in lines) {'variantId': l.variantId, 'qty': l.qty},
                ],
                'couponCode': code,
              })
              as J;
      final c = j['coupon'] as Map?;
      if (c == null) throw DomainError(tr('This coupon can’t be used on this order.'), field: 'couponCode');
      // discount = scheme discounts + coupon; total = subtotal − discount.
      final total = money(j['total']);
      return OrderQuote(
        subtotal: j['subtotal'] == null ? total + money(j['discount']) : money(j['subtotal']),
        discount: money(c['discount']),
        total: total,
        couponCode: '${c['code'] ?? code}',
        campaign: c['campaign']?.toString(),
        offer: c['offer']?.toString(),
      );
    } on ApiError catch (e) {
      throw _couponError(e);
    }
  }

  /// HOLA's coupon refusal (not valid, not running, used up…) under the field.
  DomainError _couponError(ApiError e) {
    final why = e.fields.values.firstOrNull ?? e.detail;
    if (e.code == 'COUPON_ALREADY_USED' || (e.code == 'COUPON_INVALID' && why.toLowerCase().contains('already used'))) {
      return DomainError(tr('You have already used this coupon.'), field: 'couponCode');
    }
    if (e.code == 'COUPON_RESERVED') return _reserved(RegExp(r'HO-\d+').firstMatch(why)?.group(0) ?? '');
    return e.code == 'COUPON_INVALID' ? DomainError(why.isEmpty ? tr('This coupon can’t be used.') : why, field: 'couponCode') : apiToDomain(e);
  }

  DomainError _reserved(String order) => DomainError(
    order.isEmpty
        ? tr('This coupon is on an order that hasn’t been delivered yet. If that order is cancelled, you can use it again.')
        : tr('This coupon is on order {code}, which hasn’t been delivered yet. If that order is cancelled, you can use it again.', {'code': order}),
    field: 'couponCode',
  );

  // ── HOLA product reviews (contract 0.24.0) ──

  /// HOLA's product reviews API is live.
  static bool productReviewsOn0240 = true;

  @override
  bool get productReviewsLive => api == null || productReviewsOn0240;

  /// HOLA's own figure per product, from the catalogue.
  final _ratings = <String, (double, int)>{};

  @override
  Map<String, ProductReview> productReviewsOn(String orderId) => {
    for (final r in db.productReviews)
      if (r.orderId == orderId) r.variantId: r,
  };

  @override
  bool canRateProducts(TradeOrder o) {
    if (!productReviewsLive || me?.role != Role.salonOwner || me?.salonId != o.salonId) return false;
    if (o.status != OrderStatus.delivered && o.status != OrderStatus.confirmed) return false;
    final done = productReviewsOn(o.id);
    return o.lines.any((l) => !done.containsKey(l.variantId));
  }

  @override
  (double, int) productRating(String productId) {
    if (_ratings[productId] case final r?) return r;
    final rs = db.productReviews.where((r) => r.productId == productId).toList();
    if (rs.isEmpty) return (0, 0);
    return (rs.fold(0, (s, r) => s + r.rating) / rs.length, rs.length);
  }

  @override
  Future<void> rateProducts(String orderId, Map<String, (int, String)> ratings) async {
    requireRole({Role.salonOwner});
    final o = order(orderId) ?? (throw DomainError(tr('Order not found.')));
    if (requireMe.salonId != o.salonId) throw DomainError(tr('Not your salon.'));
    if (o.status != OrderStatus.delivered && o.status != OrderStatus.confirmed) throw DomainError(tr('You can rate products once the order is delivered.'));
    final done = productReviewsOn(o.id);
    final picked = {
      for (final e in ratings.entries)
        if (e.value.$1 > 0 && !done.containsKey(e.key)) e.key: e.value,
    };
    if (picked.isEmpty) throw DomainError(tr('Give at least one product a star rating.'));
    for (final e in picked.entries) {
      if (e.value.$1 < 1 || e.value.$1 > 5) throw DomainError(tr('Ratings are 1 to 5 stars.'));
      if (!o.lines.any((l) => l.variantId == e.key)) throw DomainError(tr('That product is not on this order.'));
    }
    if (_onServer(o)) {
      if (!productReviewsOn0240) throw DomainError(tr('Product reviews open once HOLA switches them on.'));
      final lines = {for (final l in o.lines) l.variantId: l};
      if (picked.keys.any((v) => (lines[v]?.itemId ?? '').isEmpty)) throw DomainError(tr('Refresh your orders and try again.'));
      try {
        final res = await api!.post('/orders/${o.id}/product-reviews', {
          'items': [
            for (final e in picked.entries) {'orderItemId': lines[e.key]!.itemId, 'rating': e.value.$1, if (e.value.$2.trim().isNotEmpty) 'comment': e.value.$2.trim()},
          ],
        });
        final list = res is Map ? (res['data'] ?? res['items'] ?? const []) : res;
        for (final j in (list as List).cast<Map>()) {
          _keepProductReview(j, o);
        }
        if (list.isEmpty) await syncProductReviews(o.salonId);
        db.commit();
        return;
      } on ApiError catch (e) {
        if (e.status == 409) throw DomainError(tr('You already rated these products.'));
        throw apiToDomain(e);
      }
    }
    for (final e in picked.entries) {
      final l = o.lines.firstWhere((l) => l.variantId == e.key);
      db.productReviews.add(
        ProductReview(
          id: db.newId(),
          salonId: o.salonId,
          orderId: o.id,
          orderCode: o.code,
          productId: l.productId,
          variantId: l.variantId,
          name: l.name,
          rating: e.value.$1,
          comment: e.value.$2.trim(),
          createdAt: now(),
        ),
      );
    }
    db.notifyRole(Role.salesOfficer, 'New product review', '{salon} · {code}', args: {'salon': _salon(o.salonId).name, 'code': o.code}, icon: 'star', link: _link(o));
    db.commit();
  }

  /// One ProductReviewView from HOLA.
  ProductReview _keepProductReview(Map j, TradeOrder? o) {
    Map p(Object? v) => v is Map ? v : const {};
    final itemId = '${j['orderItemId'] ?? p(j['orderItem'])['id'] ?? ''}';
    final line = o?.lines.where((l) => l.itemId == itemId && itemId.isNotEmpty).firstOrNull;
    final r = ProductReview(
      id: '${j['id']}',
      salonId: '${p(j['salon'])['id'] ?? j['salonId'] ?? o?.salonId ?? ''}',
      orderId: '${p(j['order'])['id'] ?? j['orderId'] ?? o?.id ?? ''}',
      orderCode: '${p(j['order'])['code'] ?? o?.code ?? ''}',
      productId: '${p(j['product'])['id'] ?? j['productId'] ?? line?.productId ?? ''}',
      variantId: '${p(j['variant'])['id'] ?? j['variantId'] ?? line?.variantId ?? ''}',
      name: [p(j['product'])['name'] ?? j['product'], p(j['variant'])['name'] ?? j['variant']].where((v) => v is String && v.isNotEmpty).join(' · '),
      orderItemId: itemId,
      rating: asIntOr(j['rating']),
      comment: '${j['comment'] ?? ''}',
      createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal() ?? now(),
    );
    final at = db.productReviews.indexWhere((x) => x.id == r.id);
    at < 0 ? db.productReviews.add(r) : db.productReviews[at] = r;
    return r;
  }

  @override
  Future<void> syncProductReviews(String salonId) async {
    if (api == null || !productReviewsOn0240 || me?.role != Role.salonOwner) return;
    try {
      final res = await api!.get('/salons/$salonId/product-reviews', query: {'pageSize': '100'});
      final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<Map>();
      final seen = <String>{};
      for (final j in list) {
        if (j['status'] == 'DELETED') continue; // HOLA removed it
        final oid = '${(j['order'] is Map ? (j['order'] as Map)['id'] : null) ?? j['orderId'] ?? ''}';
        seen.add(_keepProductReview(j, order(oid)).id);
      }
      // HOLA deleted some.
      db.productReviews.removeWhere((r) => r.salonId == salonId && !seen.contains(r.id));
      db.commit();
    } catch (e) {
      debugPrint('Product reviews: sync failed: $e');
    }
  }

  @override
  List<ProductReview> allProductReviews() => [...db.productReviews]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> deleteProductReview(String id) async {
    requireRole({Role.salesOfficer});
    final r = db.productReviews.where((x) => x.id == id).firstOrNull ?? (throw DomainError(tr('Review not found.')));
    if (api != null && r.id.contains('-')) throw DomainError(tr('HOLA handles this in the HOLA dashboard.'));
    db.productReviews.remove(r);
    db.commit();
  }

  @override
  Future<TradeOrder> placeOrder({required String salonId, required List<CartLine> cart, required PaymentMethod payment, String notes = '', String? couponCode}) async {
    requireRole({Role.salonOwner, Role.salesOfficer});
    final me = requireMe;
    final s = _salon(salonId);
    if (me.role == Role.salonOwner && me.salonId != salonId) throw DomainError(tr('Not your salon.'));
    if (!s.isActive) throw DomainError(tr('Trade ordering opens once HOLA verifies the salon.'));
    final lines = quote(cart);
    if (lines.isEmpty) throw DomainError(tr('Your cart is empty.'));
    // HOLA's catalogue: the order goes to the server, which prices it and reserves stock.
    if (api != null && lines.every((l) => product(l.productId)?.hola ?? false)) {
      final branch = db.branches.where((b) => b.salonId == salonId && !b.id.endsWith('~delivery')).firstOrNull ?? (throw DomainError(tr('Salon not found.')));
      try {
        final res =
            await api!.post('/salons/$salonId/orders', {
                  'branchId': branch.id,
                  'paymentMethod': payment == PaymentMethod.credit ? 'CREDIT' : 'COD',
                  'items': [
                    for (final l in lines) {'variantId': l.variantId, 'qty': l.qty},
                  ],
                  if (notes.trim().isNotEmpty) 'notes': notes.trim(),
                  if (couponCode != null && couponCode.isNotEmpty) 'couponCode': couponCode,
                })
                as J;
        final o = _mirrorOrder(res, salonId, fallback: lines, payment: payment, by: me.id);
        db.commit();
        // A credit order uses up credit: fetch the new balance.
        if (payment == PaymentMethod.credit) syncCredit(salonId);
        // Its coupon is now held for this order.
        if (couponCode != null && couponCode.isNotEmpty) syncCoupons(salonId);
        // HOLA reserved the stock: refresh what's left to order.
        syncCatalogue();
        return o;
      } on ApiError catch (e) {
        if (e.code == 'INSUFFICIENT_STOCK') throw DomainError(tr('Some items are no longer in stock in that quantity. Lower the quantity and try again.'));
        if (e.code.startsWith('COUPON_')) throw _couponError(e);
        if (e.code == 'NOT_ORDERABLE') throw DomainError(tr('Some items can’t be ordered right now. Remove them and try again.'));
        throw apiToDomain(e);
      }
    }
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
    db.notifyRole(
      Role.salesOfficer,
      overLimit ? 'Order needs credit review' : 'New trade order',
      '{salon} · {code} · {amount}',
      args: {'salon': s.name, 'code': o.code, 'amount': rs(total)},
      icon: 'box',
      link: _link(o),
    );
    if (me.role == Role.salesOfficer) {
      db.notify(s.ownerId, 'Order placed for you', '{code} · {amount} by {name}', args: {'code': o.code, 'amount': rs(total), 'name': me.name}, icon: 'box', link: _link(o));
    }
    db.commit();
    return o;
  }

  /// Copies the salon's orders from the server (GET /salons/{id}/orders).
  @override
  Future<void> syncOrders(String salonId) async {
    if (api == null || me?.role != Role.salonOwner || !(db.salons.where((s) => s.id == salonId).firstOrNull?.hola ?? false)) return;
    try {
      for (var page = 1, pages = 1; page <= pages; page++) {
        final res = await api!.get('/salons/$salonId/orders', query: {'page': '$page', 'pageSize': '50'});
        final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<J>();
        if (res is Map) pages = asIntOr((res['meta'] as Map?)?['totalPages'] ?? 1);
        for (final j in list) {
          _mirrorOrder(j, salonId, fallback: const [], payment: '${j['paymentMethod']}' == 'CREDIT' ? PaymentMethod.credit : PaymentMethod.cod, by: '');
        }
      }
      db.commit();
    } catch (_) {
      // Offline: keep the last copy.
    }
    // Credit separately, so a problem with one doesn't hide the other.
    await syncCredit(salonId);
  }

  @override
  Future<void> syncCredit(String salonId) async {
    if (api == null || !{Role.salonOwner, Role.salesOfficer}.contains(me?.role)) return;
    final s = db.salons.where((s) => s.id == salonId).firstOrNull;
    if (s == null || !s.hola) return;
    try {
      final c = await api!.get('/salons/$salonId/credit') as J;
      final last = c['lastPayment'] as Map?;
      final limit = money(c['limit']);
      _serverCredit[salonId] = CreditSummary(
        limit: limit,
        outstanding: c['outstanding'] == null ? limit - money(c['available']) : money(c['outstanding']),
        // limit − outstanding − credit orders still waiting for approval.
        available: money(c['available']),
        overdue: money(c['overdue']),
        days: asIntOr(c['creditDays']),
        lastPayment: last == null ? 0 : money(last['amount']),
        lastPaymentAt: last == null ? null : DateTime.tryParse('${last['date']}'),
      );
      s
        ..creditLimit = limit
        ..creditDays = c['creditDays'] == null ? s.creditDays : asIntOr(c['creditDays']);
      db.commit();
    } catch (e) {
      debugPrint('Credit: sync failed: $e'); // offline: keep the last copy
    }
    try {
      final all = <CreditEntry>[];
      for (var page = 1, pages = 1; page <= pages && page <= 20; page++) {
        final res = await api!.get('/salons/$salonId/credit/statement', query: {'page': '$page', 'pageSize': '100'});
        final list = (res is Map ? (res['data'] ?? const []) as List : res as List).cast<Map>();
        if (res is Map) pages = asIntOr((res['meta'] as Map?)?['totalPages'] ?? 1);
        all.addAll([for (final j in list) ?_creditEntry(j, salonId)]);
      }
      _serverStatement[salonId] = all..sort((a, b) => b.at.compareTo(a.at));
      db.commit();
    } catch (e) {
      debugPrint('Credit: statement failed: $e');
    }
  }

  @override
  List<PaymentRequest> paymentRequests(String salonId) => _payRequests[salonId] ?? const [];

  /// GET /salons/{id}/coupons (contract 0.13.0).
  static const salonCouponsLive = true;
  final _coupons = <String, List<SalonCoupon>>{};

  @override
  List<SalonCoupon> coupons(String salonId) => _coupons[salonId] ?? const [];

  @override
  Future<void> syncCoupons(String salonId) async {
    if (!salonCouponsLive || !_holaSalon(salonId) || me?.role != Role.salonOwner) return;
    try {
      // Without available=true HOLA also returns used/expired/upcoming (history).
      final res = await api!.get('/salons/$salonId/coupons');
      final list = (res is Map ? (res['data'] ?? const []) as List : res as List).cast<Map>();
      _coupons[salonId] = [
        for (final j in list)
          SalonCoupon(
            id: '${j['id']}',
            code: '${j['code'] ?? ''}',
            title: '${j['title'] ?? (j['campaign'] is Map ? (j['campaign'] as Map)['name'] : j['campaign']) ?? ''}',
            campaign: '${j['campaign'] is Map ? (j['campaign'] as Map)['name'] ?? '' : j['campaign'] ?? ''}',
            description: '${j['description'] ?? ''}',
            discountText: '${j['discountText'] ?? ''}',
            usesLeft: j['usesLeft'] == null ? null : asIntOr(j['usesLeft']),
            minOrder: j['minOrderAmount'] == null ? null : money(j['minOrderAmount']),
            // appliesTo ORDER: the whole order, whatever products are listed.
            products: '${j['appliesTo'] ?? ''}' == 'ORDER' ? const [] : [for (final p in (j['products'] as List? ?? const [])) p is Map ? '${p['name'] ?? ''}' : '$p'],
            usedAt: DateTime.tryParse('${j['usedAt'] ?? ''}')?.toLocal(),
            usedOnOrder: j['usedOnOrder'] is Map ? '${(j['usedOnOrder'] as Map)['code'] ?? ''}' : '',
            reservedOnOrder: j['reservedOnOrder'] is Map ? '${(j['reservedOnOrder'] as Map)['code'] ?? ''}' : '',
            validUntil: DateTime.tryParse('${j['validUntil'] ?? ''}'),
            validFrom: DateTime.tryParse('${j['validFrom'] ?? ''}'),
            status: '${j['status'] ?? 'AVAILABLE'}'.toUpperCase(),
          ),
      ];
      db.commit();
    } catch (e) {
      debugPrint('Coupons: sync failed: $e');
    }
  }

  /// Salon picks a rider; the rider confirms in their app (proposed to HOLA,
  /// not live yet). Flip once HOLA confirms the contract.
  static const riderPickLive = true; // contract 0.15.0

  @override
  bool get canPickRider => riderPickLive;

  @override
  Future<List<RiderOption>> ridersFor(String salonId) async {
    if (!riderPickLive || !_holaSalon(salonId)) return const [];
    try {
      final res = await api!.get('/salons/$salonId/riders');
      return [
        for (final j in (res is Map ? (res['data'] ?? const []) as List : res as List).cast<Map>())
          RiderOption(id: '${j['id']}', name: '${j['fullName'] ?? ''}', phone: '${j['phone'] ?? ''}', city: '${j['city'] ?? ''}'),
      ];
    } on ApiError catch (e) {
      throw apiToDomain(e);
    }
  }

  List<CollectionRequest> _collections = const [];

  @override
  List<CollectionRequest> collections() => _collections;

  @override
  Future<void> syncCollections() async {
    if (!riderPickLive || !_serverRider) return;
    try {
      final res = await api!.get('/rider/credit-collections', query: {'status': 'PENDING'});
      _collections = [
        for (final j in (res is Map ? (res['data'] ?? const []) as List : res as List).cast<Map>())
          CollectionRequest(
            id: '${j['id']}',
            code: '${j['code'] ?? ''}',
            salonName: '${(j['salon'] as Map?)?['name'] ?? ''}',
            salonPhone: '${(j['salon'] as Map?)?['phone'] ?? ''}',
            address: '${(j['salon'] as Map?)?['address'] ?? ''}',
            amount: money(j['amount']),
            createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal() ?? now(),
          ),
      ];
      db.commit();
    } catch (e) {
      debugPrint('Collections: sync failed: $e');
    }
  }

  @override
  Future<void> confirmCollection(String id, int amount) async {
    requireRole({Role.rider});
    final c = _collections.where((x) => x.id == id).firstOrNull;
    if (amount <= 0) throw DomainError(tr('Enter the cash you took.'), field: 'amount');
    if (c != null && amount > c.amount) throw DomainError(tr('That is more than the salon is paying ({amount}).', {'amount': rs(c.amount)}), field: 'amount');
    try {
      await api!.post('/rider/credit-collections/$id/confirm', {'amount': '$amount.00'});
    } on ApiError catch (e) {
      throw apiToDomain(e);
    }
    await Future.wait([syncCollections(), syncCash()]);
  }

  @override
  Future<void> declineCollection(String id, String reason) async {
    requireRole({Role.rider});
    try {
      await api!.post('/rider/credit-collections/$id/decline', {'reason': reason.trim()});
    } on ApiError catch (e) {
      throw apiToDomain(e);
    }
    await syncCollections();
  }

  /// orderId → the credit payment the rider also collects on that delivery.
  final _creditCollections = <String, CreditCollection>{};

  @override
  CreditCollection? creditCollectionFor(String orderId) => _creditCollections[orderId];

  @override
  Future<void> collectCredit(String requestId, int amount) async {
    requireRole({Role.rider});
    if (amount <= 0) throw DomainError(tr('Enter the cash you took.'), field: 'amount');
    final asked = _creditCollections.values.where((c) => c.requestId == requestId).firstOrNull;
    if (asked != null && amount > asked.amount) throw DomainError(tr('That is more than the salon is paying ({amount}).', {'amount': rs(asked.amount)}), field: 'amount');
    try {
      await api!.post('/rider/credit-collections/$requestId', {'amount': '$amount.00'});
    } on ApiError catch (e) {
      throw apiToDomain(e);
    }
    await syncDeliveries();
    await syncCash();
  }

  @override
  int payableNow(String salonId) {
    final waiting = paymentRequests(salonId).where((r) => r.open).fold(0, (t, r) => t + (r.collectedAmount ?? r.amount));
    final left = credit(salonId).outstanding - waiting;
    return left < 0 ? 0 : left;
  }

  /// HOLA's payment-request endpoints are agreed but not live yet (contract
  /// pending the owner's approval). Flip this once HOLA says they are on staging.
  static const paymentRequestsLive = true; // contract 0.11.0

  bool _holaSalon(String salonId) => api != null && (db.salons.where((s) => s.id == salonId).firstOrNull?.hola ?? false);

  @override
  Future<void> syncPaymentRequests(String salonId) async {
    if (!paymentRequestsLive || !_holaSalon(salonId) || me?.role != Role.salonOwner) return;
    try {
      final res = await api!.get('/salons/$salonId/credit/payment-requests', query: {'page': '1', 'pageSize': '50'});
      final list = (res is Map ? (res['data'] ?? const []) as List : res as List).cast<Map>();
      _payRequests[salonId] = [for (final j in list) ?_payRequest(j, salonId)]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      db.commit();
    } catch (e) {
      debugPrint('Payments: sync failed: $e'); // not on the server yet, or offline
    }
  }

  PaymentRequest? _payRequest(Map j, String salonId) {
    final method = PayMethod.of('${j['method'] ?? ''}');
    final at = DateTime.tryParse('${j['createdAt'] ?? ''}');
    if (method == null || at == null) return null;
    String? str(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
    final by = j['collectedBy'], decided = j['decidedBy'];
    return PaymentRequest(
      id: '${j['id']}',
      code: '${j['code'] ?? ''}',
      salonId: salonId,
      method: method,
      amount: money(j['amount']),
      collectedAmount: j['collectedAmount'] == null ? null : money(j['collectedAmount']),
      confirmedAmount: j['confirmedAmount'] == null ? null : money(j['confirmedAmount']),
      status: '${j['status'] ?? 'PENDING'}'.toUpperCase(),
      reference: '${j['reference'] ?? ''}',
      note: '${j['note'] ?? ''}',
      proofFileId: str(j['proofFileId']),
      rejectReason: str(j['rejectReason']),
      collectedBy: by is Map ? str(by['fullName']) : null,
      decidedBy: decided is Map ? str(decided['fullName']) : null,
      riderName: j['rider'] is Map ? str((j['rider'] as Map)['fullName']) : null,
      createdAt: at.toLocal(),
      decidedAt: DateTime.tryParse('${j['decidedAt'] ?? ''}')?.toLocal(),
    );
  }

  @override
  Future<void> requestPayment(String salonId, {required PayMethod method, required int amount, String reference = '', String? proofPath, String note = '', String? riderId}) async {
    requireRole({Role.salonOwner});
    if (!_holaSalon(salonId)) throw DomainError(tr('Payments go through HOLA. Connect to the internet and try again.'));
    if (!paymentRequestsLive) throw DomainError(tr('Paying from the app opens soon. For now, please pay your sales officer.'));
    // Check against HOLA's latest list, never a stale copy on the phone.
    await Future.wait([syncCredit(salonId), syncPaymentRequests(salonId)]);
    final owed = payableNow(salonId);
    if (amount <= 0) throw DomainError(tr('Enter the amount you are paying.'), field: 'amount');
    if (amount > owed) {
      throw DomainError(
        owed < credit(salonId).outstanding
            ? tr('Only {amount} is left to pay: the rest is in payments already sent. Cancel one of those to pay it another way.', {'amount': rs(owed)})
            : tr('That is more than you still owe ({amount}).', {'amount': rs(owed)}),
        field: 'amount',
      );
    }
    if (method == PayMethod.online && reference.trim().isEmpty) throw DomainError(tr('Enter the transaction ID from your receipt.'), field: 'reference');
    if (method == PayMethod.online && proofPath == null) throw DomainError(tr('Add a photo of the receipt or transfer screenshot.'));
    if (method == PayMethod.rider && riderPickLive && riderId == null) throw DomainError(tr('Choose the rider you are paying.'), field: 'riderId');
    // HOLA allows one open rider payment at a time (waiting or collected).
    if (paymentRequests(salonId).where((r) => r.method == PayMethod.rider && r.open).firstOrNull case final w? when method == PayMethod.rider) {
      throw DomainError(tr('{code} for {amount} is still waiting for the rider. Cancel it on this screen to send a new one.', {'code': w.code, 'amount': rs(w.amount)}));
    }
    String? proofId;
    try {
      if (proofPath != null) {
        final bytes = await File(proofPath).readAsBytes();
        final png = proofPath.toLowerCase().endsWith('.png');
        proofId = await api!.uploadFile(bytes, contentType: png ? 'image/png' : 'image/jpeg', purpose: 'payment_proof', fileName: 'payment-proof.${png ? 'png' : 'jpg'}');
      }
      final res = await api!.post('/salons/$salonId/credit/payment-requests', {
        'method': method.api,
        'amount': '$amount.00',
        if (reference.trim().isNotEmpty) 'reference': reference.trim(),
        'proofFileId': ?proofId,
        if (note.trim().isNotEmpty) 'note': note.trim(),
        if (method == PayMethod.rider && riderPickLive) 'riderId': ?riderId,
      });
      final r = res is Map ? _payRequest(res, salonId) : null;
      if (r != null) _payRequests[salonId] = [r, ...paymentRequests(salonId).where((x) => x.id != r.id)];
      db.commit();
    } on ApiError catch (e) {
      if (e.status == 404) throw DomainError(tr('Paying from the app is not open yet. Please pay your sales officer for now.'));
      throw apiToDomain(e);
    }
  }

  @override
  Future<void> cancelPaymentRequest(String salonId, String requestId) async {
    requireRole({Role.salonOwner});
    try {
      await api!.post('/salons/$salonId/credit/payment-requests/$requestId/cancel', const {});
    } on ApiError catch (e) {
      throw apiToDomain(e);
    }
    await syncPaymentRequests(salonId);
  }

  /// One LedgerEntryView from HOLA. Its amount is signed (+ owes more,
  /// − owes less); ADJUSTMENT keeps the sign, the others carry it in [kind].
  CreditEntry? _creditEntry(Map j, String salonId) {
    final at = DateTime.tryParse('${j['createdAt'] ?? ''}');
    if (at == null) return null;
    final raw = double.tryParse('${j['amount'] ?? 0}') ?? 0;
    final type = '${j['type'] ?? ''}'.toUpperCase();
    final kind = switch (type) {
      'ORDER_CHARGE' || 'CHARGE' => 'CHARGE',
      'PAYMENT' => 'PAYMENT',
      'REVERSAL' => 'REVERSAL',
      'RETURN' => 'RETURN', // a returned product taken off (0.23.0)
      _ => 'ADJUSTMENT',
    };
    final order = j['order'];
    final ret = j['return'];
    // A RETURN line names its return in the note ("Return HR-000001 (order HO-…)").
    final retCode = j['returnCode'] ?? (ret is Map ? ret['code'] : null) ?? (kind == 'RETURN' ? RegExp(r'HR-\d+').firstMatch('${j['note'] ?? ''}')?.group(0) : null);
    final ref = '${retCode ?? j['orderCode'] ?? (order is Map ? order['code'] : null) ?? ''}';
    final bal = j['balance'];
    return CreditEntry(
      id: '${j['id'] ?? '$type-${at.toIso8601String()}'}',
      salonId: salonId,
      kind: kind,
      // Adjustments keep their sign; the other kinds say the direction themselves.
      amount: kind == 'ADJUSTMENT' ? raw.round() : raw.abs().round(),
      ref: ref == 'null' ? '' : ref,
      note: '${j['note'] ?? ''}',
      at: at.toLocal(),
      balance: bal == null ? null : money(bal),
    );
  }

  bool _onServer(TradeOrder o) => api != null && (db.salons.where((s) => s.id == o.salonId).firstOrNull?.hola ?? false) && o.id.contains('-');

  Future<void> _serverAction(TradeOrder o, String action, [Object? body]) async {
    try {
      final res = await api!.post('/orders/${o.id}/$action', body ?? const {}) as J;
      _mirrorOrder(res, o.salonId, fallback: o.lines, payment: o.payment, by: o.placedById);
      db.commit();
    } on ApiError catch (e) {
      throw apiToDomain(e);
    }
  }

  /// One server order as the app's [TradeOrder]. Unknown line shapes fall back to [fallback].
  TradeOrder _mirrorOrder(J j, String salonId, {required List<OrderLine> fallback, required PaymentMethod payment, required String by}) {
    final raw = (j['items'] ?? j['lines']) as List? ?? const [];
    final lines = [
      for (final x in raw.cast<Map>())
        OrderLine(
          productId: '${x['productId'] ?? (x['product'] is Map ? (x['product'] as Map)['id'] : '') ?? ''}',
          variantId: '${x['variantId'] ?? (x['variant'] is Map ? (x['variant'] as Map)['id'] : '') ?? ''}',
          name: [x['product'] ?? x['name'], x['variant']].where((v) => v is String && v.isNotEmpty).join(' · '),
          qty: asIntOr(x['qty'] ?? x['quantity']),
          freeQty: asIntOr(x['freeQty']),
          unitPrice: money(x['unitPrice'] ?? x['tradePrice']),
          itemId: '${x['id'] ?? x['orderItemId'] ?? ''}',
        ),
    ];
    final id = '${j['id']}';
    final old = order(id);
    final o = TradeOrder(
      id: id,
      code: '${j['code'] ?? j['number'] ?? j['orderNo'] ?? ''}',
      salonId: salonId,
      placedById: old?.placedById ?? by,
      lines: lines.isNotEmpty ? lines : (old?.lines ?? fallback),
      payment: payment,
      notes: '${j['notes'] ?? ''}',
      status: '${j['status'] ?? OrderStatus.placed}',
      history: _history(old, j, by),
      createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? now(),
    );
    o
      ..riderId = old?.riderId
      ..recipientName = old?.recipientName
      ..cashCollected = old?.cashCollected
      ..failReason = old?.failReason
      ..handoverId = old?.handoverId
      ..signature = old?.signature
      ..deliveredWhere = old?.deliveredWhere;
    // A replacement HOLA made for a return (contract 0.23.0).
    if (j['replacementOf'] case final Map r) {
      o
        ..replacementFor = '${r['returnCode'] ?? r['code'] ?? ''}'
        ..replacementOfOrder = '${r['orderCode'] ?? old?.replacementOfOrder ?? ''}';
    } else {
      o
        ..replacementFor = old?.replacementFor
        ..replacementOfOrder = old?.replacementOfOrder;
    }
    final coupon = j['coupon'];
    if (coupon is Map) {
      o
        ..couponCode = '${coupon['code'] ?? ''}'
        ..discount = money(coupon['discount']);
    } else if (j.containsKey('coupon')) {
      o
        ..couponCode = null
        ..discount = 0;
    } else {
      o
        ..couponCode = old?.couponCode
        ..discount = old?.discount ?? 0;
    }
    _applyDelivery(o, j['delivery']);
    final at = db.orders.indexWhere((x) => x.id == id);
    at < 0 ? db.orders.add(o) : db.orders[at] = o;
    return o;
  }

  /// The order's steps so far: what this phone already had, plus the
  /// server's current status when it moved on (with the cancel reason).
  List<StatusEvent> _history(TradeOrder? old, J j, String by) {
    final status = '${j['status'] ?? OrderStatus.placed}';
    final h = [...?old?.history];
    if (h.isEmpty || h.last.status != status) {
      final when =
          DateTime.tryParse('${j['cancelledAt'] ?? j['statusChangedAt'] ?? j['updatedAt'] ?? ''}')?.toLocal() ?? (h.isEmpty ? DateTime.tryParse('${j['createdAt']}')?.toLocal() : null) ?? now();
      final reason = status == OrderStatus.cancelled ? '${j['cancelReason'] ?? j['cancellationReason'] ?? j['reason'] ?? ''}'.trim() : '';
      h.add(StatusEvent(status, when, by, reason.isEmpty ? null : reason));
    }
    return h;
  }

  /// HOLA's delivery block on an order: who received it, the cash, why it
  /// failed, and when each step happened.
  void _applyDelivery(TradeOrder o, Object? raw) {
    if (raw is! Map) return;
    final d = raw;
    if (d['recipientName'] is String) o.recipientName = d['recipientName'] as String;
    // The delivery's rider (salon side), so the salon can message them.
    if (d['rider'] case final Map r when r['id'] is String) {
      o.riderId = r['id'] as String;
      mirrorPerson(db, o.riderId!, '${r['fullName'] ?? r['name'] ?? ''}', role: Role.rider, phone: '${r['phone'] ?? ''}');
    } else if (d['riderId'] is String) {
      o.riderId = d['riderId'] as String;
    }
    if (d['cashCollected'] != null) o.cashCollected = money(d['cashCollected']);
    if (d['failReason'] is String) o.failReason = d['failReason'] as String;
    DateTime? t(String k) => DateTime.tryParse('${d[k]}')?.toLocal();
    final steps = [
      if (t('assignedAt') case final at?) StatusEvent(OrderStatus.dispatched, at, ''),
      if (t('startedAt') case final at?) StatusEvent(OrderStatus.outForDelivery, at, ''),
      if (t('deliveredAt') case final at?) StatusEvent(OrderStatus.delivered, at, ''),
    ];
    if (steps.isNotEmpty) {
      o.history
        ..removeWhere((e) => steps.any((s) => s.status == e.status))
        ..addAll(steps)
        ..sort((a, b) => a.at.compareTo(b.at));
    }
  }

  // ── rider (HOLA server) ──

  bool get _serverRider => api != null && me?.role == Role.rider;
  Future<void>? _deliveriesSync;

  @override
  Future<void> syncDeliveries() => _deliveriesSync ??= _syncDeliveries().whenComplete(() => _deliveriesSync = null);

  Future<void> _syncDeliveries() async {
    if (!_serverRider) return;
    final riderId = me!.id;
    try {
      final res = await api!.get('/rider/deliveries', query: {'all': 'true'});
      final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<J>();
      final seen = <String>{};
      for (final j in list) {
        final o = _mirrorDelivery(j);
        o.riderId = riderId;
        seen.add(o.id);
      }
      // Re-assigned to someone else or withdrawn by the office.
      db.orders.removeWhere((o) => o.riderId == riderId && o.id.contains('-') && !seen.contains(o.id));
      db.commit();
    } catch (e) {
      debugPrint('Deliveries: sync failed: $e'); // offline: keep the last copy
    }
  }

  /// One delivery from GET /rider/deliveries: the order, plus the salon and
  /// the address it goes to, so the rider can find and call them.
  TradeOrder _mirrorDelivery(J j) {
    final salon = (j['salon'] as Map?) ?? const {};
    final to = (j['deliveryTo'] as Map?) ?? const {};
    final salonId = '${salon['id'] ?? ''}';
    var s = db.salons.where((x) => x.id == salonId).firstOrNull;
    if (s == null) {
      s = Salon(id: salonId, ownerId: '', name: '${salon['name'] ?? ''}', phone: '', status: SalonStatus.active, palette: salonId.hashCode.abs() % 6, hola: true, createdAt: now());
      db.salons.add(s);
    }
    if (salon['name'] is String) s.name = salon['name'] as String;
    if (to['phone'] is String && (to['phone'] as String).isNotEmpty) s.phone = to['phone'] as String;
    // The owner to call (0.10.0); null when HOLA has no owner on file.
    final owner = salon['owner'];
    if (owner is Map) {
      final n = '${owner['fullName'] ?? ''}'.trim(), p = '${owner['phone'] ?? ''}'.trim();
      s
        ..ownerName = n.isEmpty ? null : n
        ..ownerPhone = p.isEmpty ? null : p;
    } else if (salon.containsKey('owner')) {
      s
        ..ownerName = null
        ..ownerPhone = null;
    }
    // The address snapshot from when the order was placed.
    final b = to['branch'];
    final branchId = '${b is Map ? b['id'] : to['branchId'] ?? j['branchId'] ?? '$salonId~delivery'}';
    final branchName = '${b is Map ? b['name'] ?? '' : b ?? ''}';
    var br = db.branches.where((x) => x.id == branchId).firstOrNull;
    if (br == null) {
      br = Branch(id: branchId, salonId: salonId, name: branchName, address: '', area: '', city: '');
      db.branches.add(br);
    }
    br
      ..name = branchName.isEmpty ? br.name : branchName
      ..address = '${to['addressLine'] ?? br.address}'
      ..area = '${to['area'] ?? br.area}'
      ..city = '${to['city'] ?? br.city}'
      ..location = branchGeo(to) ?? br.location
      ..mapsUrl = to['mapsUrl'] is String && (to['mapsUrl'] as String).startsWith('https://') ? to['mapsUrl'] as String : br.mapsUrl;
    final o = _mirrorOrder(j, salonId, fallback: const [], payment: '${j['paymentMethod']}' == 'CREDIT' ? PaymentMethod.credit : PaymentMethod.cod, by: '');
    // The salon may also pay its credit balance to the rider (contract 0.11.0).
    final cc = j['creditCollection'];
    if (cc is Map && cc['requestId'] != null) {
      _creditCollections[o.id] = CreditCollection(requestId: '${cc['requestId']}', code: '${cc['code'] ?? ''}', amount: money(cc['amount']));
    } else {
      _creditCollections.remove(o.id);
    }
    return o;
  }

  @override
  bool needsDeliveryPhoto(String id) {
    final o = order(id);
    return o != null && _onServer(o);
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
    _phoneOnly();
    final o = _order(id);
    _move(o, OrderStatus.approved, {OrderStatus.placed, OrderStatus.underReview});
    db.notify(_salon(o.salonId).ownerId, 'Order approved', '{code} is being packed.', args: {'code': o.code}, icon: 'check', link: _link(o));
    db.commit();
  }

  @override
  Future<void> cancelOrder(String id, String reason) async {
    final o = _order(id);
    final me = requireMe;
    if (_onServer(o)) {
      if (reason.trim().length < 3) throw DomainError(tr('Add the reason for cancelling.'));
      await _serverAction(o, 'cancel', {'reason': reason.trim()});
      // A coupon on this order is free to use again.
      if (o.couponCode?.isNotEmpty ?? false) await syncCoupons(o.salonId).catchError((Object _) {});
      // Its stock goes back on sale.
      syncCatalogue();
      return;
    }
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
    _phoneOnly();
    final o = _order(id);
    final rider = db.accounts.where((a) => a.id == riderId && a.role == Role.rider).firstOrNull ?? (throw DomainError(tr('Pick a rider.')));
    _move(o, OrderStatus.dispatched, {OrderStatus.approved, OrderStatus.failed}, note: rider.name);
    o
      ..riderId = rider.id
      ..failReason = null;
    final s = _salon(o.salonId);
    final b = db.branches.where((b) => b.salonId == s.id && !b.id.endsWith('~delivery')).firstOrNull;
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
    if (_onServer(o)) return _serverAction(o, 'start-delivery');
    _move(o, OrderStatus.outForDelivery, {OrderStatus.dispatched});
    db.notify(_salon(o.salonId).ownerId, 'On the way', '{code} is out for delivery with {name}.', args: {'code': o.code, 'name': requireMe.name}, icon: 'truck', link: _link(o));
    db.commit();
  }

  @override
  Future<void> deliver(String id, {required String recipientName, required Strokes signature, int? cashCollected, GeoFix? where, String? photoPath}) async {
    final o = _riderOrder(id);
    if (recipientName.trim().length < 2) throw DomainError(tr('Enter who received the order.'));
    if (_onServer(o)) {
      if (o.isCod && cashCollected != o.total) throw DomainError(tr('Collect exactly {amount} for this cash order.', {'amount': rs(o.total)}));
      final f = photoPath == null ? null : File(photoPath);
      if (f == null || !f.existsSync()) throw DomainError(tr('Take a photo of the delivered order.'));
      final String photoId;
      try {
        photoId = await api!.uploadFile(await f.readAsBytes(), contentType: 'image/jpeg', purpose: 'delivery_proof', fileName: 'delivery-${o.code}.jpg');
      } catch (e) {
        throw apiToDomain(e);
      }
      // HOLA wants the cash as its own decimal text, equal to the order total
      // (e.g. "3760.00"), so send the total exactly as the server holds it.
      var cash = '$cashCollected.00';
      if (o.isCod) {
        try {
          final cur = await api!.get('/orders/${o.id}') as J;
          if (cur['total'] != null && money(cur['total']) == cashCollected) cash = '${cur['total']}';
        } catch (_) {}
      }
      await _serverAction(o, 'deliver', {'recipientName': recipientName.trim(), 'photoId': photoId, if (o.isCod) 'cashCollected': cash});
      // Kept on the phone: the signature and where it was handed over.
      order(id)
        ?..signature = signature
        ..deliveredWhere = where;
      db.commit();
      return;
    }
    if (signature.where((s) => s.length > 1).isEmpty) throw DomainError(tr('Ask the recipient to sign.'));
    if (o.isCod && cashCollected != o.total) throw DomainError(tr('Collect exactly {amount} for this cash order.', {'amount': rs(o.total)}));
    _move(o, OrderStatus.delivered, {OrderStatus.outForDelivery});
    o
      ..recipientName = recipientName.trim()
      ..signature = signature
      ..cashCollected = o.isCod ? cashCollected : null
      ..deliveredWhere = where;
    db.notify(
      _salon(o.salonId).ownerId,
      'Order delivered',
      '{code} received by {name}. Please confirm the items.',
      args: {'code': o.code, 'name': o.recipientName ?? ''},
      icon: 'check',
      link: _link(o),
    );
    db.notifyRole(Role.salesOfficer, 'Delivered', '{salon} · {code}', args: {'salon': _salon(o.salonId).name, 'code': o.code}, icon: 'check', link: _link(o));
    db.commit();
  }

  @override
  Future<void> failDelivery(String id, String reason) async {
    final o = _riderOrder(id);
    if (reason.trim().length < 3) throw DomainError(tr('Say why it could not be delivered.'));
    if (_onServer(o)) return _serverAction(o, 'fail-delivery', {'reason': reason.trim()});
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
    if (_onServer(o)) return _serverAction(o, 'confirm-receipt');
    _move(o, OrderStatus.confirmed, {OrderStatus.delivered});
    db.commit();
  }

  // ── credit ──

  @override
  CreditSummary credit(String salonId) {
    final server = _serverCredit[salonId];
    if (server != null) return server;
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
    final lastPay = entries.lastWhere(
      (e) => e.kind == 'PAYMENT',
      orElse: () => CreditEntry(id: '', salonId: '', kind: '', amount: 0, ref: '', at: DateTime(0)),
    );
    return CreditSummary(limit: s.creditLimit, outstanding: outstanding, overdue: overdue, days: s.creditDays, lastPayment: lastPay.amount, lastPaymentAt: lastPay.id.isEmpty ? null : lastPay.at);
  }

  @override
  List<CreditEntry> statement(String salonId) => _serverStatement[salonId] ?? db.credit.where((e) => e.salonId == salonId).toList()
    ..sort((a, b) => b.at.compareTo(a.at));

  @override
  Future<void> setCreditTerms(String salonId, {required int limit, required int days}) async {
    requireRole({Role.salesOfficer});
    _phoneOnly();
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
    _phoneOnly();
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
  List<TradeOrder> cashOnHand(String riderId) =>
      db.orders.where((o) => o.riderId == riderId && o.isCod && o.handoverId == null && (o.status == OrderStatus.delivered || o.status == OrderStatus.confirmed)).toList();

  /// The rider's cash in hand as HOLA counts it (null until fetched).
  List<CashPayment>? _serverCash;

  @override
  List<CashPayment> cashHeld(String riderId) => _serverRider && _serverCash != null
      ? _serverCash!
      : [for (final o in cashOnHand(riderId)) CashPayment(id: o.id, orderCode: o.code, amount: o.cashCollected ?? 0, receivedAt: o.at(OrderStatus.delivered))];

  @override
  Future<void> syncCash() async {
    if (!_serverRider) return;
    try {
      final j = await api!.get('/rider/cash') as J;
      _serverCash = [
        for (final p in (j['payments'] as List? ?? const []).cast<Map>())
          CashPayment(
            id: '${p['id']}',
            orderCode: '${p['orderCode'] ?? ''}',
            amount: money(p['amount']),
            receivedAt: DateTime.tryParse('${p['receivedAt']}')?.toLocal(),
            creditPayment: '${p['kind']}' == 'CREDIT_PAYMENT',
            requestCode: '${p['requestCode'] ?? ''}',
            salonName: switch (p['salon']) {
              final Map s => '${s['name'] ?? ''}',
              final String s => s,
              _ => '',
            },
          ),
      ];
      await _syncHandovers();
      db.commit();
    } catch (e) {
      debugPrint('Cash: sync failed: $e'); // offline: keep the last copy
    }
  }

  /// HOLA's list of this rider's hand-overs, with what finance confirmed.
  Future<void> _syncHandovers() async {
    final me = requireMe.id;
    final res = await api!.get('/rider/cash-handovers');
    final list = (res is Map ? (res['data'] as List? ?? const []) : res as List).cast<Map>();
    final seen = <String>{};
    for (final h in list) {
      final id = '${h['id']}';
      seen.add(id);
      final codes = {
        for (final p in (h['payments'] as List? ?? const []).cast<Map>())
          if (p['orderCode'] != null) '${p['orderCode']}',
      };
      final ho = CashHandover(
        id: id,
        riderId: me,
        orderIds: [
          for (final o in db.orders)
            if (codes.contains(o.code)) o.id,
        ],
        amount: money(h['amount']),
        at: DateTime.tryParse('${h['createdAt']}')?.toLocal() ?? now(),
        status: '${h['status'] ?? 'PENDING'}',
        confirmedById: (h['confirmedBy'] as Map?)?['id'] as String?,
        confirmedAt: DateTime.tryParse('${h['confirmedAt'] ?? ''}')?.toLocal(),
        paymentCount: (h['payments'] as List?)?.length,
      );
      for (final o in db.orders.where((o) => codes.contains(o.code))) {
        o.handoverId = id;
      }
      final i = db.handovers.indexWhere((x) => x.id == id);
      i < 0 ? db.handovers.add(ho) : db.handovers[i] = ho;
    }
    // Hand-overs HOLA doesn't have (merged, or from an older build) go.
    db.handovers.removeWhere((x) => x.riderId == me && !seen.contains(x.id));
  }

  /// POST /rider/cash-handovers with every payment the rider holds.
  Future<CashHandover> _serverHandOver() async {
    await syncCash();
    final held = _serverCash ?? const [];
    if (held.isEmpty) throw DomainError(tr('You have no cash to hand over.'));
    final J h;
    try {
      h =
          await api!.post('/rider/cash-handovers', {
                'paymentIds': [for (final p in held) p.id],
              })
              as J;
    } on ApiError catch (e) {
      if (e.code == 'INVALID_REFERENCE' || e.status == 409) {
        await syncCash();
        throw DomainError(tr('Your cash changed. Check the amount and try again.'));
      }
      throw apiToDomain(e);
    }
    final codes = [for (final p in (h['payments'] as List? ?? const []).cast<Map>()) '${p['orderCode'] ?? ''}'];
    final ho = CashHandover(
      id: '${h['id']}',
      riderId: requireMe.id,
      orderIds: [
        for (final o in db.orders)
          if (codes.contains(o.code)) o.id,
      ],
      amount: money(h['amount']),
      at: DateTime.tryParse('${h['createdAt']}')?.toLocal() ?? now(),
      status: '${h['status'] ?? 'PENDING'}',
    );
    for (final o in db.orders.where((o) => codes.contains(o.code))) {
      o.handoverId = ho.id;
    }
    db.handovers.add(ho);
    _serverCash = [];
    db.commit();
    return ho;
  }

  @override
  Future<CashHandover> handOverCash() async {
    requireRole({Role.rider});
    if (_serverRider) return _serverHandOver();
    final me = requireMe;
    final os = cashOnHand(me.id);
    if (os.isEmpty) throw DomainError(tr('You have no cash to hand over.'));
    final h = CashHandover(id: db.newId(), riderId: me.id, orderIds: [for (final o in os) o.id], amount: os.fold(0, (t, o) => t + (o.cashCollected ?? 0)), at: now());
    for (final o in os) {
      o.handoverId = h.id;
    }
    db.handovers.add(h);
    db.notifyRole(
      Role.salesOfficer,
      'Cash handed over',
      os.length == 1 ? '{name} · {amount} for {n} delivery. Please confirm.' : '{name} · {amount} for {n} deliveries. Please confirm.',
      args: {'name': me.name, 'amount': rs(h.amount), 'n': '${os.length}'},
      icon: 'cash',
    );
    db.commit();
    return h;
  }

  @override
  List<CashHandover> handovers({String? riderId}) => db.handovers.where((h) => riderId == null || h.riderId == riderId).toList()..sort((a, b) => b.at.compareTo(a.at));

  @override
  Future<void> confirmHandover(String id) async {
    requireRole({Role.salesOfficer});
    _phoneOnly();
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

/// One product from GET /catalog/trade, as the app's [Product].
Product mirrorProduct(Map j, int i) {
  final id = '${j['productId'] ?? j['id']}';
  final name = '${j['product'] ?? j['name'] ?? ''}';
  final variants = [
    for (final v in (j['variants'] as List? ?? const []).cast<Map>())
      Variant(
        id: '${v['id']}',
        name: '${v['name'] ?? v['shadeCode'] ?? v['sku'] ?? ''}',
        tradePrice: money(v['tradePrice']),
        retailPrice: money(v['retailPrice']),
        // How many can be ordered; without a count, in stock means orderable.
        stock: v['available'] is num ? (v['available'] as num).toInt() : (v['inStock'] == false ? 0 : 999),
        sku: v['sku'] is String ? v['sku'] as String : '',
        size: v['size'] is String ? v['size'] as String : '',
      ),
  ];
  // The first current scheme: buy N, get M free.
  var buy = 0, free = 0;
  final schemes = [for (final v in (j['variants'] as List? ?? const []).cast<Map>()) ...(v['schemes'] as List? ?? const []).cast<Map>(), ...(j['schemes'] as List? ?? const []).cast<Map>()];
  final bxgy = schemes.where((x) => x['type'] == 'BUY_X_GET_Y').firstOrNull;
  if (bxgy != null) {
    buy = asIntOr(bxgy['buyQty']);
    free = asIntOr(bxgy['freeQty']);
  }
  const colours = [0xFF2F80FF, 0xFF7A5BE0, 0xFF169C8F, 0xFFE08A2E, 0xFFD94C7A, 0xFF3D4A66];
  return Product(
    id: id,
    name: name,
    category: '${j['category'] ?? 'Hair Care'}',
    description: '${j['description'] ?? ''}',
    color: colours[id.hashCode.abs() % colours.length],
    variants: variants,
    schemeBuy: buy,
    schemeFree: free,
    createdAt: DateTime(2026),
    imageUrl: j['imageUrl'] is String ? j['imageUrl'] as String : '',
    imageUrls: [
      for (final u in (j['imageUrls'] as List? ?? const []))
        if (u is String) u,
    ],
    brand: j['brand'] is String ? j['brand'] as String : '',
    hola: true,
  );
}

int asIntOr(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
