import '../../core/l10n/l10n.dart';
import 'appointment.dart' show StatusEvent;
import 'geo.dart';
import 'json.dart';

/// Product categories for the HOLA trade catalogue. Fixed vocabulary.
const productCategories = ['Colour', 'Care', 'Styling', 'Treatment', 'Tools'];

/// A sellable variant (size or shade) of a HOLA product.
class Variant {
  final String id;
  String name; // e.g. "7.1 Ash Blonde" or "1 L"
  int tradePrice, retailPrice, stock;

  /// HOLA's stock code, as the dashboard shows it.
  String sku;

  /// Pack size from the dashboard, e.g. "1000 ML" (contract 0.28.0).
  String size;
  Variant({required this.id, required this.name, required this.tradePrice, required this.retailPrice, required this.stock, this.sku = '', this.size = ''});
  Json toJson() => {'id': id, 'name': name, 'tradePrice': tradePrice, 'retailPrice': retailPrice, 'stock': stock, 'sku': sku, 'size': size};
  factory Variant.fromJson(Json j) =>
      Variant(id: j['id'], name: j['name'], tradePrice: asInt(j['tradePrice']), retailPrice: asInt(j['retailPrice']), stock: asInt(j['stock']), sku: j['sku'] ?? '', size: j['size'] ?? '');
}

class Product {
  final String id;
  String name, category, description;
  int color; // bottle colour (ARGB)
  String shape; // '' bottle | 'tube' | 'jar' | 'drop' (Bottle widget shapes)
  final List<Variant> variants;

  /// Scheme: buy [schemeBuy], get [schemeFree] free (0 = none).
  int schemeBuy, schemeFree;
  bool active;
  final DateTime createdAt;

  /// Product photo from HOLA (https), shown instead of the drawn bottle.
  String imageUrl;

  /// All of HOLA's photos, main one first (the dashboard's upload order).
  List<String> imageUrls;

  /// Brand, as set in the HOLA dashboard.
  String brand;

  /// Comes from the HOLA server catalogue (ordered through the server).
  bool hola;

  Product({
    required this.id,
    required this.name,
    required this.category,
    this.description = '',
    required this.color,
    this.shape = '',
    required this.variants,
    this.schemeBuy = 0,
    this.schemeFree = 0,
    this.active = true,
    required this.createdAt,
    this.imageUrl = '',
    List<String>? imageUrls,
    this.brand = '',
    this.hola = false,
  }) : imageUrls = imageUrls ?? [];

  /// Photos to show, main first; empty when HOLA has none.
  List<String> get photos => [
    for (final u in {if (imageUrl.isNotEmpty) imageUrl, ...imageUrls})
      if (u.startsWith('https://')) u,
  ];

  bool get hasScheme => schemeBuy > 0 && schemeFree > 0;
  String get schemeLabel => hasScheme ? tr('Buy {buy} get {free}', {'buy': schemeBuy, 'free': schemeFree}) : '';
  int freeFor(int qty) => hasScheme ? (qty ~/ schemeBuy) * schemeFree : 0;
  int get fromPrice => variants.isEmpty ? 0 : variants.map((v) => v.tradePrice).reduce((a, b) => a < b ? a : b);

  Json toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'description': description,
    'color': color,
    'shape': shape,
    'variants': [for (final v in variants) v.toJson()],
    'schemeBuy': schemeBuy,
    'schemeFree': schemeFree,
    'active': active,
    'createdAt': iso(createdAt),
    'imageUrl': imageUrl,
    'imageUrls': imageUrls,
    'brand': brand,
    'hola': hola,
  };
  factory Product.fromJson(Json j) => Product(
    id: j['id'],
    name: j['name'],
    category: j['category'],
    description: j['description'] ?? '',
    color: asInt(j['color']),
    shape: j['shape'] ?? '',
    variants: objs(j['variants'], Variant.fromJson),
    schemeBuy: asInt(j['schemeBuy']),
    schemeFree: asInt(j['schemeFree']),
    active: j['active'] ?? true,
    createdAt: dt(j['createdAt'])!,
    imageUrl: j['imageUrl'] ?? '',
    imageUrls: strs(j['imageUrls']),
    brand: j['brand'] ?? '',
    hola: j['hola'] ?? false,
  );
}

class OrderLine {
  final String productId, variantId, name;

  /// HOLA's order item id (empty for an on-device order); returns name it.
  final String itemId;
  final int qty, freeQty, unitPrice;
  const OrderLine({required this.productId, required this.variantId, required this.name, required this.qty, required this.freeQty, required this.unitPrice, this.itemId = ''});
  int get total => qty * unitPrice;
  Json toJson() => {'productId': productId, 'variantId': variantId, 'name': name, 'qty': qty, 'freeQty': freeQty, 'unitPrice': unitPrice, if (itemId.isNotEmpty) 'itemId': itemId};
  factory OrderLine.fromJson(Json j) =>
      OrderLine(productId: j['productId'], variantId: j['variantId'], name: j['name'], qty: asInt(j['qty']), freeQty: asInt(j['freeQty']), unitPrice: asInt(j['unitPrice']), itemId: j['itemId'] ?? '');
}

abstract final class OrderStatus {
  static const placed = 'PLACED', underReview = 'UNDER_REVIEW', approved = 'APPROVED', dispatched = 'DISPATCHED', outForDelivery = 'OUT_FOR_DELIVERY';
  static const delivered = 'DELIVERED', confirmed = 'CONFIRMED', cancelled = 'CANCELLED', failed = 'FAILED_DELIVERY';
  static const flow = [placed, approved, dispatched, outForDelivery, delivered, confirmed];
  static const open = {placed, underReview, approved, dispatched, outForDelivery, failed};
}

enum PaymentMethod { credit, cod }

/// Signature as strokes of points in a unit square (0..1).
typedef Strokes = List<List<(double, double)>>;

class TradeOrder {
  final String id, code, salonId, placedById;
  final List<OrderLine> lines;
  final PaymentMethod payment;
  final String notes;
  String status;
  String? riderId, recipientName, failReason, handoverId;
  int? cashCollected;
  Strokes? signature;

  /// Where the rider was when the order was handed over (null if GPS was unavailable).
  GeoFix? deliveredWhere;

  /// A HOLA coupon used on the order, and what it took off.
  String? couponCode;

  /// Set on a replacement order HOLA made for a return: that return's code
  /// and the original order's code. A replacement costs the salon nothing.
  String? replacementFor, replacementOfOrder;
  int discount;
  final List<StatusEvent> history;
  final DateTime createdAt;

  TradeOrder({
    required this.id,
    required this.code,
    required this.salonId,
    required this.placedById,
    required this.lines,
    required this.payment,
    this.notes = '',
    required this.status,
    this.riderId,
    this.recipientName,
    this.failReason,
    this.handoverId,
    this.cashCollected,
    this.signature,
    this.deliveredWhere,
    this.couponCode,
    this.discount = 0,
    this.replacementFor,
    this.replacementOfOrder,
    List<StatusEvent>? history,
    required this.createdAt,
  }) : history = history ?? [];

  int get subtotal => lines.fold(0, (s, l) => s + l.total);
  int get total => subtotal - discount;
  int get units => lines.fold(0, (s, l) => s + l.qty + l.freeQty);
  bool get isCod => payment == PaymentMethod.cod;
  DateTime? at(String s) {
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].status == s) return history[i].at;
    }
    return null;
  }

  Json toJson() => {
    'id': id,
    'code': code,
    'salonId': salonId,
    'placedById': placedById,
    'lines': [for (final l in lines) l.toJson()],
    'payment': payment.name,
    'notes': notes,
    'status': status,
    'riderId': riderId,
    'recipientName': recipientName,
    'failReason': failReason,
    'handoverId': handoverId,
    'cashCollected': cashCollected,
    'deliveredWhere': deliveredWhere?.toJson(),
    if (couponCode != null) 'couponCode': couponCode,
    if (discount != 0) 'discount': discount,
    if (replacementFor != null) 'replacementFor': replacementFor,
    if (replacementOfOrder != null) 'replacementOfOrder': replacementOfOrder,
    'signature': signature == null
        ? null
        : [
            for (final s in signature!)
              [
                for (final p in s) [p.$1, p.$2],
              ],
          ],
    'history': [for (final h in history) h.toJson()],
    'createdAt': iso(createdAt),
  };

  factory TradeOrder.fromJson(Json j) => TradeOrder(
    id: j['id'],
    code: j['code'],
    salonId: j['salonId'],
    placedById: j['placedById'],
    lines: objs(j['lines'], OrderLine.fromJson),
    payment: PaymentMethod.values.byName(j['payment']),
    notes: j['notes'] ?? '',
    replacementFor: j['replacementFor'],
    replacementOfOrder: j['replacementOfOrder'],
    status: j['status'],
    riderId: j['riderId'],
    recipientName: j['recipientName'],
    deliveredWhere: GeoFix.fromJson(j['deliveredWhere']),
    failReason: j['failReason'],
    handoverId: j['handoverId'],
    cashCollected: j['cashCollected'] == null ? null : asInt(j['cashCollected']),
    couponCode: j['couponCode'],
    discount: asInt(j['discount']),
    signature: j['signature'] == null
        ? null
        : [
            for (final s in (j['signature'] as List)) [for (final p in (s as List)) (asDouble((p as List)[0]), asDouble(p[1]))],
          ],
    history: objs(j['history'], StatusEvent.fromJson),
    createdAt: dt(j['createdAt'])!,
  );
}

/// A coupon HOLA sent this salon: shown as a promotion and usable on a
/// HOLA order (code goes in the order's couponCode).
class SalonCoupon {
  final String id, code, title, campaign, description;

  /// "20% off" / "Rs 500 off", as HOLA words it.
  final String discountText;
  final int? usesLeft;

  /// Smallest order (or spend on the products on offer) it works on.
  final int? minOrder;

  /// Products it's for (empty, or appliesTo ORDER: the whole order).
  final List<String> products;

  /// When and on which order this salon used it.
  final DateTime? usedAt;
  final String usedOnOrder;

  /// The active order holding it (status RESERVED). It is freed if that
  /// order is cancelled, and used for good once the order completes.
  final String reservedOnOrder;

  /// Last day it can be used (a whole day, Karachi time), and first day.
  final DateTime? validUntil, validFrom;

  /// AVAILABLE | RESERVED (on an active order) | UPCOMING (campaign not started) | USED | EXPIRED
  final String status;
  const SalonCoupon({
    required this.id,
    required this.code,
    required this.title,
    this.campaign = '',
    this.description = '',
    this.discountText = '',
    this.usesLeft,
    this.minOrder,
    this.products = const [],
    this.usedAt,
    this.usedOnOrder = '',
    this.reservedOnOrder = '',
    this.validUntil,
    this.validFrom,
    this.status = 'AVAILABLE',
  });

  /// HOLA decides (dates, uses left, campaign running).
  bool get available => status == 'AVAILABLE';
  bool get used => status == 'USED' || usedAt != null;
  bool get reserved => status == 'RESERVED';
}

/// HOLA's price for a cart, with a coupon applied when given.
class OrderQuote {
  /// [discount] is the coupon's part; [total] is HOLA's final price.
  final int subtotal, discount, total;

  /// The coupon that was applied (null when none was given).
  final String? couponCode, campaign, offer;
  const OrderQuote({required this.subtotal, required this.discount, required this.total, this.couponCode, this.campaign, this.offer});
}

/// Salon credit ledger line: a CREDIT order charges, a payment reduces.
class CreditEntry {
  /// CHARGE (an order on credit) | PAYMENT | REVERSAL (a cancelled order) |
  /// ADJUSTMENT (HOLA's correction; [amount] is signed, + adds to what is owed).
  final String id, salonId, kind;
  final int amount;
  final String ref, note;
  final DateTime at;

  /// What the salon owed after this line, when HOLA sends it.
  final int? balance;
  const CreditEntry({required this.id, required this.salonId, required this.kind, required this.amount, required this.ref, this.note = '', required this.at, this.balance});

  /// How this line changes what the salon owes (+ owes more, − owes less).
  int get effect => switch (kind) {
    'CHARGE' => amount,
    'ADJUSTMENT' => amount,
    _ => -amount,
  };
  Json toJson() => {'id': id, 'salonId': salonId, 'kind': kind, 'amount': amount, 'ref': ref, 'note': note, 'at': iso(at)};
  factory CreditEntry.fromJson(Json j) => CreditEntry(id: j['id'], salonId: j['salonId'], kind: j['kind'], amount: asInt(j['amount']), ref: j['ref'] ?? '', note: j['note'] ?? '', at: dt(j['at'])!);
}

/// How a salon pays off its HOLA credit balance.
enum PayMethod {
  /// Cash to the rider on the next delivery.
  rider,

  /// Cash straight to HOLA (office or sales officer).
  cash,

  /// Bank transfer / JazzCash / Easypaisa, with a receipt for HOLA to check.
  online;

  String get api => switch (this) {
    rider => 'RIDER',
    cash => 'CASH_AT_OFFICE',
    online => 'ONLINE',
  };
  static PayMethod? of(String s) => values.where((m) => m.api == s.toUpperCase()).firstOrNull;
}

/// A salon's "I'm paying this" note. HOLA finance confirms the money, and
/// only then does it reach the credit statement as a payment.
class PaymentRequest {
  final String id, code, salonId;
  final PayMethod method;
  final int amount;

  /// What the rider took ([collectedAmount]) and what finance counted
  /// ([confirmedAmount]); either may be less than [amount].
  final int? collectedAmount, confirmedAmount;

  /// PENDING | COLLECTED (rider has the cash) | PAID (rider confirmed) |
  /// CONFIRMED | REJECTED | CANCELLED
  final String status;
  final String reference, note;
  final String? proofFileId, rejectReason, collectedBy, decidedBy;

  /// The rider the salon chose to pay (RIDER method).
  final String? riderName;
  final DateTime createdAt;
  final DateTime? decidedAt;
  const PaymentRequest({
    required this.id,
    this.code = '',
    required this.salonId,
    required this.method,
    required this.amount,
    this.collectedAmount,
    this.confirmedAmount,
    required this.status,
    this.reference = '',
    this.note = '',
    this.proofFileId,
    this.rejectReason,
    this.collectedBy,
    this.decidedBy,
    this.riderName,
    required this.createdAt,
    this.decidedAt,
  });
  bool get open => status == 'PENDING' || status == 'COLLECTED';

  /// Done: the money reached HOLA's books.
  bool get paid => status == 'PAID' || status == 'CONFIRMED';

  /// The most certain amount so far: counted, else collected, else asked.
  int get shown => confirmedAmount ?? collectedAmount ?? amount;
}

/// A HOLA rider a salon can hand its credit payment to.
class RiderOption {
  final String id, name, phone, city;
  const RiderOption({required this.id, required this.name, this.phone = '', this.city = ''});
}

/// Rider app: a salon chose this rider to pay its HOLA balance to.
class CollectionRequest {
  final String id, code, salonName, salonPhone, address;
  final int amount;
  final DateTime createdAt;
  const CollectionRequest({required this.id, required this.code, required this.salonName, this.salonPhone = '', this.address = '', required this.amount, required this.createdAt});
}

/// A salon's credit payment the rider should also collect on this delivery.
class CreditCollection {
  final String requestId, code;
  final int amount;
  const CreditCollection({required this.requestId, required this.code, required this.amount});
}

/// Cash a rider hands over for COD deliveries; HOLA confirms receipt.
/// Cash a rider collected and still holds (one delivered COD order).
class CashPayment {
  final String id, orderCode;
  final int amount;
  final DateTime? receivedAt;

  /// A salon paying its credit balance (PR-…) rather than a COD order.
  final bool creditPayment;
  final String requestCode, salonName;
  const CashPayment({required this.id, required this.orderCode, required this.amount, this.receivedAt, this.creditPayment = false, this.requestCode = '', this.salonName = ''});
}

class CashHandover {
  final String id, riderId;
  final List<String> orderIds;
  final int amount;
  final DateTime at;
  String status; // PENDING | CONFIRMED
  String? confirmedById;
  DateTime? confirmedAt;

  /// Cash amounts handed over: deliveries plus salon credit payments, which
  /// have no order of their own (HOLA sends the count).
  final int? paymentCount;
  int get items => paymentCount ?? orderIds.length;
  CashHandover({
    required this.id,
    required this.riderId,
    required this.orderIds,
    required this.amount,
    required this.at,
    this.status = 'PENDING',
    this.confirmedById,
    this.confirmedAt,
    this.paymentCount,
  });
  Json toJson() => {
    'id': id,
    'riderId': riderId,
    'orderIds': orderIds,
    'amount': amount,
    'at': iso(at),
    'status': status,
    'confirmedById': confirmedById,
    'confirmedAt': iso(confirmedAt),
    if (paymentCount != null) 'paymentCount': paymentCount,
  };
  factory CashHandover.fromJson(Json j) => CashHandover(
    id: j['id'],
    riderId: j['riderId'],
    orderIds: strs(j['orderIds']),
    amount: asInt(j['amount']),
    at: dt(j['at'])!,
    status: j['status'],
    confirmedById: j['confirmedById'],
    confirmedAt: dt(j['confirmedAt']),
    paymentCount: j['paymentCount'] == null ? null : asInt(j['paymentCount']),
  );
}

/// A salon's rating of a HOLA product it ordered and received. These are
/// HOLA's (its dashboard), never mixed with customers' salon reviews.
class ProductReview {
  final String id, salonId, orderId, orderCode, productId, variantId, name;

  /// HOLA's order item id (empty for an on-device order).
  final String orderItemId;
  final int rating;
  final String comment;
  final DateTime createdAt;
  const ProductReview({
    required this.id,
    required this.salonId,
    required this.orderId,
    this.orderCode = '',
    required this.productId,
    required this.variantId,
    required this.name,
    this.orderItemId = '',
    required this.rating,
    this.comment = '',
    required this.createdAt,
  });
  Json toJson() => {
    'id': id,
    'salonId': salonId,
    'orderId': orderId,
    'orderCode': orderCode,
    'productId': productId,
    'variantId': variantId,
    'name': name,
    'orderItemId': orderItemId,
    'rating': rating,
    'comment': comment,
    'createdAt': iso(createdAt),
  };
  factory ProductReview.fromJson(Json j) => ProductReview(
    id: j['id'],
    salonId: j['salonId'],
    orderId: j['orderId'],
    orderCode: j['orderCode'] ?? '',
    productId: j['productId'] ?? '',
    variantId: j['variantId'] ?? '',
    name: j['name'] ?? '',
    orderItemId: j['orderItemId'] ?? '',
    rating: asInt(j['rating']),
    comment: j['comment'] ?? '',
    createdAt: dt(j['createdAt'])!,
  );
}
