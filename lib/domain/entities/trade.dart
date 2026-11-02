import '../../core/l10n/l10n.dart';
import 'appointment.dart' show StatusEvent;
import 'json.dart';

/// Product categories for the HOLA trade catalogue. Fixed vocabulary.
const productCategories = ['Colour', 'Care', 'Styling', 'Treatment', 'Tools'];

/// A sellable variant (size or shade) of a HOLA product.
class Variant {
  final String id;
  String name; // e.g. "7.1 Ash Blonde" or "1 L"
  int tradePrice, retailPrice, stock;
  Variant({required this.id, required this.name, required this.tradePrice, required this.retailPrice, required this.stock});
  Json toJson() => {'id': id, 'name': name, 'tradePrice': tradePrice, 'retailPrice': retailPrice, 'stock': stock};
  factory Variant.fromJson(Json j) => Variant(id: j['id'], name: j['name'], tradePrice: asInt(j['tradePrice']), retailPrice: asInt(j['retailPrice']), stock: asInt(j['stock']));
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

  Product({required this.id, required this.name, required this.category, this.description = '', required this.color, this.shape = '', required this.variants, this.schemeBuy = 0, this.schemeFree = 0, this.active = true, required this.createdAt});

  bool get hasScheme => schemeBuy > 0 && schemeFree > 0;
  String get schemeLabel => hasScheme ? tr('Buy {buy} get {free}', {'buy': schemeBuy, 'free': schemeFree}) : '';
  int freeFor(int qty) => hasScheme ? (qty ~/ schemeBuy) * schemeFree : 0;
  int get fromPrice => variants.isEmpty ? 0 : variants.map((v) => v.tradePrice).reduce((a, b) => a < b ? a : b);

  Json toJson() => {
        'id': id, 'name': name, 'category': category, 'description': description, 'color': color, 'shape': shape, 'variants': [for (final v in variants) v.toJson()],
        'schemeBuy': schemeBuy, 'schemeFree': schemeFree, 'active': active, 'createdAt': iso(createdAt),
      };
  factory Product.fromJson(Json j) => Product(
        id: j['id'], name: j['name'], category: j['category'], description: j['description'] ?? '', color: asInt(j['color']), shape: j['shape'] ?? '',
        variants: objs(j['variants'], Variant.fromJson), schemeBuy: asInt(j['schemeBuy']), schemeFree: asInt(j['schemeFree']), active: j['active'] ?? true,
        createdAt: dt(j['createdAt'])!,
      );
}

class OrderLine {
  final String productId, variantId, name;
  final int qty, freeQty, unitPrice;
  const OrderLine({required this.productId, required this.variantId, required this.name, required this.qty, required this.freeQty, required this.unitPrice});
  int get total => qty * unitPrice;
  Json toJson() => {'productId': productId, 'variantId': variantId, 'name': name, 'qty': qty, 'freeQty': freeQty, 'unitPrice': unitPrice};
  factory OrderLine.fromJson(Json j) => OrderLine(productId: j['productId'], variantId: j['variantId'], name: j['name'], qty: asInt(j['qty']), freeQty: asInt(j['freeQty']), unitPrice: asInt(j['unitPrice']));
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
    List<StatusEvent>? history,
    required this.createdAt,
  }) : history = history ?? [];

  int get total => lines.fold(0, (s, l) => s + l.total);
  int get units => lines.fold(0, (s, l) => s + l.qty + l.freeQty);
  bool get isCod => payment == PaymentMethod.cod;
  DateTime? at(String s) {
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].status == s) return history[i].at;
    }
    return null;
  }

  Json toJson() => {
        'id': id, 'code': code, 'salonId': salonId, 'placedById': placedById, 'lines': [for (final l in lines) l.toJson()], 'payment': payment.name, 'notes': notes,
        'status': status, 'riderId': riderId, 'recipientName': recipientName, 'failReason': failReason, 'handoverId': handoverId, 'cashCollected': cashCollected,
        'signature': signature == null ? null : [for (final s in signature!) [for (final p in s) [p.$1, p.$2]]],
        'history': [for (final h in history) h.toJson()], 'createdAt': iso(createdAt),
      };

  factory TradeOrder.fromJson(Json j) => TradeOrder(
        id: j['id'], code: j['code'], salonId: j['salonId'], placedById: j['placedById'], lines: objs(j['lines'], OrderLine.fromJson),
        payment: PaymentMethod.values.byName(j['payment']), notes: j['notes'] ?? '', status: j['status'], riderId: j['riderId'], recipientName: j['recipientName'],
        failReason: j['failReason'], handoverId: j['handoverId'], cashCollected: j['cashCollected'] == null ? null : asInt(j['cashCollected']),
        signature: j['signature'] == null
            ? null
            : [for (final s in (j['signature'] as List)) [for (final p in (s as List)) (asDouble((p as List)[0]), asDouble(p[1]))]],
        history: objs(j['history'], StatusEvent.fromJson), createdAt: dt(j['createdAt'])!,
      );
}

/// Salon credit ledger line: a CREDIT order charges, a payment reduces.
class CreditEntry {
  final String id, salonId, kind; // CHARGE | PAYMENT
  final int amount;
  final String ref, note;
  final DateTime at;
  const CreditEntry({required this.id, required this.salonId, required this.kind, required this.amount, required this.ref, this.note = '', required this.at});
  Json toJson() => {'id': id, 'salonId': salonId, 'kind': kind, 'amount': amount, 'ref': ref, 'note': note, 'at': iso(at)};
  factory CreditEntry.fromJson(Json j) => CreditEntry(id: j['id'], salonId: j['salonId'], kind: j['kind'], amount: asInt(j['amount']), ref: j['ref'] ?? '', note: j['note'] ?? '', at: dt(j['at'])!);
}

/// Cash a rider hands over for COD deliveries; HOLA confirms receipt.
class CashHandover {
  final String id, riderId;
  final List<String> orderIds;
  final int amount;
  final DateTime at;
  String status; // PENDING | CONFIRMED
  String? confirmedById;
  DateTime? confirmedAt;
  CashHandover({required this.id, required this.riderId, required this.orderIds, required this.amount, required this.at, this.status = 'PENDING', this.confirmedById, this.confirmedAt});
  Json toJson() => {'id': id, 'riderId': riderId, 'orderIds': orderIds, 'amount': amount, 'at': iso(at), 'status': status, 'confirmedById': confirmedById, 'confirmedAt': iso(confirmedAt)};
  factory CashHandover.fromJson(Json j) => CashHandover(
        id: j['id'], riderId: j['riderId'], orderIds: strs(j['orderIds']), amount: asInt(j['amount']), at: dt(j['at'])!, status: j['status'],
        confirmedById: j['confirmedById'], confirmedAt: dt(j['confirmedAt']),
      );
}
