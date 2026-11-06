import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';

/// One order, with what the signed-in role may do with it.
class OrderDetailViewModel extends RepoViewModel {
  OrderDetailViewModel(this.trade, this.salons, this.auth, this.id, {this.chat, this.returns}) : super(trade);
  final TradeRepository trade;
  final ReturnRepository? returns;
  final ChatRepository? chat;
  final SalonRepository salons;
  final AuthRepository auth;
  final String id;

  TradeOrder? get order => trade.order(id);
  Salon? get salon => order == null ? null : salons.salon(order!.salonId);
  Branch? get branch => order == null ? null : salons.branches(order!.salonId).firstOrNull;
  Account? get rider => order?.riderId == null ? null : auth.account(order!.riderId!);
  Account? get placedBy => order == null ? null : auth.account(order!.placedById);
  Role? get role => auth.current?.role;
  CreditSummary? get credit => order == null ? null : trade.credit(order!.salonId);
  List<Account> get riders => auth.accountsWithRole(Role.rider);
  Product? product(String id) => trade.product(id);

  bool get isOwner => role == Role.salonOwner;
  bool get isOfficer => role == Role.salesOfficer;
  String get status => order?.status ?? '';

  /// The salon can chat with the rider who has (or had) this delivery.
  bool get canMessageRider =>
      isOwner &&
      order?.riderId != null &&
      (chat?.live ?? false) &&
      {OrderStatus.dispatched, OrderStatus.outForDelivery, OrderStatus.delivered, OrderStatus.failed, OrderStatus.confirmed}.contains(status);
  bool get canOwnerCancel => isOwner && {OrderStatus.placed, OrderStatus.underReview}.contains(status);
  bool get canConfirmReceipt => isOwner && status == OrderStatus.delivered;
  // With HOLA connected, approving and dispatching happen in the HOLA dashboard.
  bool get canApprove => isOfficer && trade.officerToolsOnPhone && {OrderStatus.placed, OrderStatus.underReview}.contains(status);
  bool get canDispatch => isOfficer && trade.officerToolsOnPhone && {OrderStatus.approved, OrderStatus.failed}.contains(status);
  bool get canOfficerCancel => isOfficer && {OrderStatus.placed, OrderStatus.underReview, OrderStatus.approved, OrderStatus.dispatched, OrderStatus.failed}.contains(status);

  /// The salon can send products from this delivered order back.
  bool get canReturn => isOwner && order != null && (returns?.live ?? false) && returns!.canReturn(order!);
  List<ReturnRequest> get orderReturns => returns?.returnsForOrder(id) ?? const [];

  /// The salon rates the HOLA products it received.
  bool get canRate => order != null && trade.canRateProducts(order!);
  Map<String, ProductReview> get myRatings => trade.productReviewsOn(id);
  Future<void> rate(Map<String, (int, String)> ratings) => trade.rateProducts(id, ratings);

  Future<void> approve() => trade.approveOrder(id);
  Future<void> dispatch(String riderId) => trade.dispatch(id, riderId);
  Future<void> cancel(String reason) => trade.cancelOrder(id, reason);
  Future<void> confirmReceipt() => trade.confirmReceipt(id);
}

enum OrderFilter { open, delivered, all }

class SalonOrdersViewModel extends RepoViewModel {
  SalonOrdersViewModel(this.trade, this.salons, this.salonId) : super(trade) {
    trade.syncCatalogue(); // HOLA's current products and prices
    trade.syncOrders(salonId);
    trade.syncCoupons(salonId);
  }

  /// HOLA's offers for this salon that can still be used.
  List<SalonCoupon> get offers => trade.coupons(salonId).where((c) => c.available).toList();
  final TradeRepository trade;
  final SalonRepository salons;
  final String salonId;
  OrderFilter filter = OrderFilter.open;

  Salon? get salon => salons.salon(salonId);
  List<TradeOrder> get all => trade.ordersForSalon(salonId);
  List<TradeOrder> get orders => switch (filter) {
    OrderFilter.open => all.where((o) => OrderStatus.open.contains(o.status)).toList(),
    OrderFilter.delivered => all.where((o) => o.status == OrderStatus.delivered || o.status == OrderStatus.confirmed).toList(),
    OrderFilter.all => all,
  };
  int get openCount => all.where((o) => OrderStatus.open.contains(o.status)).length;

  /// HOLA products to show on the salon's Today screen.
  List<Product> get featured => trade.products().take(8).toList();

  void setFilter(OrderFilter f) {
    filter = f;
    notify();
  }
}

/// Catalogue browsing + cart for one salon. Cart is keyed by variant.
class NewOrderViewModel extends RepoViewModel {
  /// Salons' rating of a HOLA product: (average, count).
  (double, int) rating(Product p) => trade.productRating(p.id);

  NewOrderViewModel(this.trade, this.salons, this.salonId, {this.suggestedCoupon}) : super(trade) {
    trade.syncCatalogue();
    trade.syncCoupons(salonId);
    trade.syncCredit(salonId); // the latest limit and balance before paying on credit
  }
  final TradeRepository trade;
  final SalonRepository salons;
  final String salonId;

  String? category;
  String query = '';
  final Map<String, String> _variantOf = {}; // productId → chosen variant
  final Map<(String, String), int> _cart = {}; // (productId, variantId) → qty
  PaymentMethod? _payment;
  String notes = '';

  Salon? get salon => salons.salon(salonId);

  /// HOLA gave this salon a credit line (udhar), so it can order on credit.
  bool get hasCredit => credit.limit > 0;
  CreditSummary get credit => trade.credit(salonId);
  PaymentMethod get payment => _payment ?? (hasCredit ? PaymentMethod.credit : PaymentMethod.cod);

  List<Product> get allProducts => trade.products();
  List<String> get categories => [
    for (final c in productCategories)
      if (allProducts.any((p) => p.category == c)) c,
  ];
  List<Product> get products {
    final q = query.trim().toLowerCase();
    return allProducts.where((p) {
      if (category != null && p.category != category) return false;
      if (q.isEmpty) return true;
      return '${p.name} ${p.category} ${p.variants.map((v) => v.name).join(' ')}'.toLowerCase().contains(q);
    }).toList();
  }

  Variant variantFor(Product p) {
    final id = _variantOf[p.id];
    return p.variants.where((v) => v.id == id).firstOrNull ?? p.variants.where((v) => v.stock > 0).firstOrNull ?? p.variants.first;
  }

  int qty(Product p, Variant v) => _cart[(p.id, v.id)] ?? 0;

  /// Highest qty that still leaves stock for the scheme's free units.
  int maxQty(Product p, Variant v) {
    var q = v.stock;
    while (q > 0 && q + p.freeFor(q) > v.stock) {
      q--;
    }
    return q;
  }

  void pickVariant(Product p, Variant v) {
    _variantOf[p.id] = v.id;
    notify();
  }

  void setQty(Product p, Variant v, int q) {
    if (q <= 0) {
      _cart.remove((p.id, v.id));
    } else {
      _cart[(p.id, v.id)] = q;
    }
    notify();
    _requote();
  }

  // ── coupon ──
  /// Code from the promotion the salon tapped, applied on review.
  String? suggestedCoupon;

  /// HOLA's coupons for this salon that can still be used.
  List<SalonCoupon> get availableCoupons => trade.coupons(salonId).where((c) => c.available).toList();

  /// HOLA's price with the coupon applied (null when there is no coupon).
  OrderQuote? coupon;
  String? couponError;
  bool couponBusy = false;

  /// The code last checked, so the box shows which coupon an error is about.
  String triedCode = '';
  int get discount => coupon?.discount ?? 0;

  /// Checks [code] with HOLA and applies its discount, or shows why not.
  Future<void> applyCoupon(String code) async {
    if (code.trim().isEmpty) return;
    triedCode = code.trim().toUpperCase();
    couponBusy = true;
    couponError = null;
    notify();
    try {
      coupon = await trade.quoteWithCoupon(salonId: salonId, cart: cart, couponCode: code);
    } on DomainError catch (e) {
      coupon = null;
      couponError = e.message;
    } catch (_) {
      coupon = null;
      couponError = tr('Couldn’t check the coupon. Try again.');
    }
    couponBusy = false;
    notify();
  }

  void removeCoupon() {
    coupon = null;
    couponError = null;
    notify();
  }

  /// The cart changed: ask HOLA again so the discount stays right.
  void _requote() {
    final c = coupon?.couponCode;
    if (c == null) return;
    if (_cart.isEmpty) return removeCoupon();
    applyCoupon(c);
  }

  void setCategory(String? c) {
    category = c;
    notify();
  }

  void setQuery(String q) {
    query = q;
    notify();
  }

  void setPayment(PaymentMethod m) {
    _payment = m;
    notify();
  }

  @override
  void refresh() {
    // Drop lines whose product or variant disappeared or went inactive.
    _cart.removeWhere((k, _) => trade.product(k.$1)?.variants.any((v) => v.id == k.$2) != true || trade.product(k.$1)?.active != true);
  }

  List<CartLine> get cart => [for (final e in _cart.entries) CartLine(e.key.$1, e.key.$2, e.value)];
  List<OrderLine> get lines => trade.quote(cart);
  int get subtotal => lines.fold(0, (s, l) => s + l.total);

  /// HOLA's quoted total while a coupon is on; otherwise the cart's own sum.
  int get total => coupon?.total ?? subtotal;
  int get units => lines.fold(0, (s, l) => s + l.qty + l.freeQty);
  int get freeUnits => lines.fold(0, (s, l) => s + l.freeQty);
  bool get isEmpty => _cart.isEmpty;
  bool get overLimit => payment == PaymentMethod.credit && total > credit.available;

  Future<TradeOrder> place() async {
    final o = await trade.placeOrder(salonId: salonId, cart: cart, payment: payment, notes: notes, couponCode: coupon?.couponCode);
    // Start fresh: the Products tab keeps this cart while it's open.
    _cart.clear();
    notes = '';
    coupon = null;
    couponError = null;
    notify();
    return o;
  }

  /// Product and variant behind a cart line (null if it left the catalogue).
  (Product, Variant)? _of(OrderLine l) {
    final p = trade.product(l.productId);
    final v = p?.variants.where((x) => x.id == l.variantId).firstOrNull;
    return p == null || v == null ? null : (p, v);
  }

  Product? productOf(OrderLine l) => _of(l)?.$1;
  int maxFor(OrderLine l) => switch (_of(l)) {
    (final p, final v) => maxQty(p, v),
    _ => l.qty,
  };

  /// Change a line's quantity from the review; 0 removes it.
  void setLineQty(OrderLine l, int q) {
    if (_of(l) case (final p, final v)) {
      setQty(p, v, q);
    } else {
      _cart.removeWhere((k, _) => k.$1 == l.productId && k.$2 == l.variantId);
      notify();
    }
  }
}

/// Credit ledger line with the balance after it.
class LedgerRow {
  final CreditEntry entry;
  final int balance;
  const LedgerRow(this.entry, this.balance);
}

class StatementViewModel extends RepoViewModel {
  StatementViewModel(this.trade, this.salons, this.auth, this.salonId) : super(trade) {
    trade.syncCredit(salonId);
    trade.syncPaymentRequests(salonId);
  }

  /// Pull-to-refresh.
  Future<void> pull() => Future.wait([trade.syncCredit(salonId), trade.syncPaymentRequests(salonId)]);

  /// Payments the salon told HOLA about (newest first).
  List<PaymentRequest> get payments => trade.paymentRequests(salonId);
  Future<void> cancelPayment(String id) => trade.cancelPaymentRequest(salonId, id);
  final TradeRepository trade;
  final SalonRepository salons;
  final AuthRepository auth;
  final String salonId;

  Salon? get salon => salons.salon(salonId);
  CreditSummary get credit => trade.credit(salonId);
  bool get isOfficer => auth.current?.role == Role.salesOfficer;

  /// Credit terms and recording payments: on-device only (HOLA dashboard otherwise).
  bool get canManage => isOfficer && trade.officerToolsOnPhone;

  /// Entries drawn at once; the newest first, 100 more on "Show more".
  int shown = 100;
  void showMore() {
    shown += 100;
    notify();
  }

  /// Newest first, each with the running balance after it.
  List<LedgerRow> get ledger {
    final oldest = trade.statement(salonId).reversed;
    var bal = 0;
    final rows = <LedgerRow>[];
    for (final e in oldest) {
      bal = e.balance ?? bal + e.effect;
      rows.add(LedgerRow(e, bal));
    }
    return rows.reversed.toList();
  }

  Future<void> recordPayment(int amount, String note) => trade.recordPayment(salonId, amount, note);
  Future<void> setTerms(int limit, int days) => trade.setCreditTerms(salonId, limit: limit, days: days);
}

class ProductsAdminViewModel extends RepoViewModel {
  ProductsAdminViewModel(this.trade) : super(trade);
  final TradeRepository trade;
  static const lowStock = 10;

  /// Adding, editing and restocking products: on-device only. With HOLA
  /// connected the list is read-only (Products and Inventory in the dashboard).
  bool get canEdit => trade.officerToolsOnPhone;

  String? category;
  List<Product> get all => trade.products(activeOnly: false);
  List<Product> get products => all.where((p) => category == null || p.category == category).toList();
  int get lowCount => all.where((p) => p.active && p.variants.any((v) => v.stock < lowStock)).length;

  void setCategory(String? c) {
    category = c;
    notify();
  }

  Future<void> restock(Product p, Variant v, int qty) => trade.restock(p.id, v.id, qty);
}

/// Editable copy of a variant row in the product form.
class VariantDraft {
  final String id;
  String name, trade, retail, stock;
  VariantDraft({required this.id, this.name = '', this.trade = '', this.retail = '', this.stock = ''});
}

class ProductEditorViewModel extends RepoViewModel {
  ProductEditorViewModel(this.trade, this.productId) : super(trade) {
    final p = productId == null ? null : trade.product(productId!);
    if (p != null) {
      name = p.name;
      category = p.category;
      description = p.description;
      color = p.color;
      shape = p.shape;
      schemeBuy = p.schemeBuy;
      schemeFree = p.schemeFree;
      active = p.active;
      variants.addAll([for (final v in p.variants) VariantDraft(id: v.id, name: v.name, trade: '${v.tradePrice}', retail: v.retailPrice == 0 ? '' : '${v.retailPrice}', stock: '${v.stock}')]);
    } else {
      addVariant();
    }
  }
  final TradeRepository trade;
  final String? productId;

  static const colors = [0xFF005BAC, 0xFF771913, 0xFFFF8A00, 0xFF14854E, 0xFF6B4E9B, 0xFF13111C, 0xFF0E8A9A, 0xFFF2EFE6];
  static const shapes = [('', 'Bottle'), ('tube', 'Tube'), ('jar', 'Jar'), ('drop', 'Dropper')];

  String name = '', category = productCategories.first, description = '';
  int color = colors.first;
  String shape = '';
  int schemeBuy = 0, schemeFree = 0;
  bool active = true;
  final variants = <VariantDraft>[];
  int _seq = 0;

  bool get isNew => productId == null;
  bool get hasScheme => schemeBuy > 0;

  void set(void Function() f) {
    f();
    notify();
  }

  void addVariant() {
    variants.add(VariantDraft(id: 'v${DateTime.now().microsecondsSinceEpoch}${_seq++}'));
    notify();
  }

  void removeVariant(VariantDraft v) {
    variants.remove(v);
    notify();
  }

  void toggleScheme(bool on) {
    schemeBuy = on ? 6 : 0;
    schemeFree = on ? 1 : 0;
    notify();
  }

  int _n(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  Future<Product> save() => trade.saveProduct(
    id: productId,
    name: name,
    category: category,
    description: description,
    color: color,
    shape: shape,
    variants: [for (final v in variants) Variant(id: v.id, name: v.name.trim(), tradePrice: _n(v.trade), retailPrice: _n(v.retail), stock: _n(v.stock))],
    schemeBuy: schemeBuy,
    schemeFree: schemeFree,
    active: active,
  );
}

/// Paying off the salon's HOLA credit: how much, and how (rider, cash at the
/// office, or online with a receipt). HOLA confirms before it counts.
class PayOutstandingViewModel extends RepoViewModel {
  PayOutstandingViewModel(this.trade, this.salonId) : super(trade) {
    trade.syncCredit(salonId);
    trade.syncPaymentRequests(salonId);
    if (trade.canPickRider) loadRiders();
  }

  // ── pay a rider of your choice ──
  bool get pickRider => trade.canPickRider;
  List<RiderOption> riders = const [];
  bool ridersLoading = false;
  String? ridersError;
  RiderOption? rider;

  Future<void> loadRiders() async {
    ridersLoading = true;
    ridersError = null;
    notify();
    try {
      riders = await trade.ridersFor(salonId);
      if (rider != null && riders.every((r) => r.id != rider!.id)) rider = null;
    } on DomainError catch (e) {
      ridersError = e.message;
    } catch (_) {
      ridersError = tr('Couldn’t load riders. Pull down to try again.');
    }
    ridersLoading = false;
    notify();
  }

  void setRider(RiderOption r) {
    rider = r;
    notify();
  }

  final TradeRepository trade;
  final String salonId;

  CreditSummary get credit => trade.credit(salonId);

  /// Payments already sent that still hold part of the balance.
  List<PaymentRequest> get openRequests => trade.paymentRequests(salonId).where((r) => r.open).toList();
  Future<void> cancelRequest(PaymentRequest r) => trade.cancelPaymentRequest(salonId, r.id);
  Future<void> pull() => Future.wait([trade.syncCredit(salonId), trade.syncPaymentRequests(salonId)]);

  /// Owed now, less payments already waiting for HOLA.
  int get payable => trade.payableNow(salonId);
  int get waiting => credit.outstanding - payable;

  /// Rider, or straight to HOLA ([direct]) by cash or online.
  PayMethod method = PayMethod.rider;
  bool get direct => method != PayMethod.rider;
  String? proofPath;

  void setMethod(PayMethod m) {
    method = m;
    notify();
  }

  void setProof(String? path) {
    proofPath = path;
    notify();
  }

  Future<void> submit({required int amount, String reference = ''}) => trade.requestPayment(
    salonId,
    method: method,
    amount: amount,
    reference: reference,
    proofPath: method == PayMethod.online ? proofPath : null,
    riderId: method == PayMethod.rider ? rider?.id : null,
  );
}
