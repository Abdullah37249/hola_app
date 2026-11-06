import 'json.dart';

/// What the salon asks for when it returns delivered products.
abstract final class ReturnOption {
  /// New units of the same products, sent as a replacement order.
  static const replace = 'REPLACE';

  /// Money back: taken off the outstanding balance for a credit order; for a
  /// cash-on-delivery order HOLA proposes a voucher or a replacement (never
  /// cash back).
  static const refund = 'REFUND';
}

/// Why the products go back.
abstract final class ReturnReason {
  static const expired = 'EXPIRED', damaged = 'DAMAGED', wrongItem = 'WRONG_ITEM', mismatch = 'MISMATCH', other = 'OTHER';
  static const all = [expired, damaged, wrongItem, mismatch, other];
}

/// The reason in words (English; show it through tr()).
String returnReasonLabel(String reason) => switch (reason) {
  ReturnReason.expired => 'Expired product',
  ReturnReason.damaged => 'Damaged product',
  ReturnReason.wrongItem => 'Wrong product',
  ReturnReason.mismatch => 'Doesn’t match the order',
  _ => 'Other reason',
};

/// Where a return request stands (HOLA contract 0.23.0).
///
/// REQUESTED → UNDER_REVIEW (⇄ RESPONSE_SENT) → [cash refund only:
/// AWAITING_SALON_CONFIRMATION] → APPROVED → PICKUP_ASSIGNED → the rider
/// collects the goods and the settlement runs → COMPLETED, or
/// REPLACEMENT_ORDER_CREATED until the replacement arrives. Or REJECTED /
/// CANCELLED.
abstract final class ReturnStatus {
  static const requested = 'REQUESTED', underReview = 'UNDER_REVIEW', responseSent = 'RESPONSE_SENT', awaitingSalon = 'AWAITING_SALON_CONFIRMATION';
  static const approved = 'APPROVED', pickupAssigned = 'PICKUP_ASSIGNED', replacementCreated = 'REPLACEMENT_ORDER_CREATED';
  static const completed = 'COMPLETED', rejected = 'REJECTED', cancelled = 'CANCELLED';

  /// Not settled yet: its units can't go into another request.
  static const open = {requested, underReview, responseSent, awaitingSalon, approved, pickupAssigned};

  /// HOLA hasn't decided yet.
  static const undecided = {requested, underReview, responseSent};

  /// The salon may withdraw it while HOLA hasn't decided.
  static const cancellable = undecided;
}

/// How HOLA proposes to settle a cash order's money-back return.
abstract final class Settlement {
  static const voucher = 'VOUCHER', replace = 'REPLACE';
}

/// One returned product line.
class ReturnItem {
  /// HOLA's order item id (empty for an on-device order).
  final String orderItemId, variantId, name;
  final int qty, unitPrice;
  const ReturnItem({this.orderItemId = '', required this.variantId, required this.name, required this.qty, required this.unitPrice});
  int get total => qty * unitPrice;
  Json toJson() => {'orderItemId': orderItemId, 'variantId': variantId, 'name': name, 'qty': qty, 'unitPrice': unitPrice};
  factory ReturnItem.fromJson(Json j) =>
      ReturnItem(orderItemId: j['orderItemId'] ?? '', variantId: j['variantId'] ?? '', name: j['name'] ?? '', qty: asInt(j['qty']), unitPrice: asInt(j['unitPrice']));
}

/// HOLA's offer for a cash order: a voucher, or replacing the products.
class ReturnProposal {
  final String settlement;
  final int amount;
  final DateTime? validUntil;
  final String note;
  final DateTime proposedAt;
  const ReturnProposal({required this.settlement, required this.amount, this.validUntil, this.note = '', required this.proposedAt});
  Json toJson() => {'settlement': settlement, 'amount': amount, 'validUntil': iso(validUntil), 'note': note, 'proposedAt': iso(proposedAt)};
  factory ReturnProposal.fromJson(Json j) =>
      ReturnProposal(settlement: j['settlement'], amount: asInt(j['amount']), validUntil: dt(j['validUntil']), note: j['note'] ?? '', proposedAt: dt(j['proposedAt'])!);
}

/// The voucher a salon gets for a cash order's return.
class ReturnVoucher {
  final String id, code, status;
  final int amount;
  final DateTime? validUntil;
  const ReturnVoucher({required this.id, required this.code, required this.amount, this.validUntil, this.status = 'ACTIVE'});
  Json toJson() => {'id': id, 'code': code, 'amount': amount, 'validUntil': iso(validUntil), 'status': status};
  factory ReturnVoucher.fromJson(Json j) => ReturnVoucher(id: j['id'], code: j['code'], amount: asInt(j['amount']), validUntil: dt(j['validUntil']), status: j['status'] ?? 'ACTIVE');
}

/// How a return was settled once the rider collected the goods.
abstract final class SettlementType {
  static const creditAdjusted = 'CREDIT_ADJUSTED', voucher = 'VOUCHER', replacement = 'REPLACEMENT';
}

class ReturnSettlement {
  final String type;
  final int amount;
  final ReturnVoucher? voucher;
  final String? replacementOrderId, replacementOrderCode;
  const ReturnSettlement({required this.type, required this.amount, this.voucher, this.replacementOrderId, this.replacementOrderCode});
  Json toJson() => {'type': type, 'amount': amount, 'voucher': voucher?.toJson(), 'replacementOrderId': replacementOrderId, 'replacementOrderCode': replacementOrderCode};
  factory ReturnSettlement.fromJson(Json j) => ReturnSettlement(
    type: j['type'],
    amount: asInt(j['amount']),
    voucher: j['voucher'] == null ? null : ReturnVoucher.fromJson(Map<String, dynamic>.from(j['voucher'])),
    replacementOrderId: j['replacementOrderId'],
    replacementOrderCode: j['replacementOrderCode'],
  );
}

/// The rider HOLA sends to pick the returned goods up.
class ReturnPickup {
  final String riderId, riderName;
  final DateTime assignedAt;
  final DateTime? expectedOn;
  DateTime? collectedAt;
  ReturnPickup({required this.riderId, this.riderName = '', required this.assignedAt, this.expectedOn, this.collectedAt});
  Json toJson() => {'riderId': riderId, 'riderName': riderName, 'assignedAt': iso(assignedAt), 'expectedOn': iso(expectedOn), 'collectedAt': iso(collectedAt)};
  factory ReturnPickup.fromJson(Json j) =>
      ReturnPickup(riderId: j['riderId'], riderName: j['riderName'] ?? '', assignedAt: dt(j['assignedAt'])!, expectedOn: dt(j['expectedOn']), collectedAt: dt(j['collectedAt']));
}

/// One step in a return's audit trail: who (SALON / HOLA / RIDER) did what.
class ReturnEvent {
  final String status, by, side, action, note;
  final DateTime at;
  const ReturnEvent(this.status, this.at, {this.by = '', this.side = '', this.action = '', this.note = ''});
  Json toJson() => {'status': status, 'at': iso(at), 'by': by, 'side': side, 'action': action, 'note': note};
  factory ReturnEvent.fromJson(Json j) => ReturnEvent(j['status'], dt(j['at'])!, by: j['by'] ?? '', side: j['side'] ?? '', action: j['action'] ?? '', note: j['note'] ?? '');
}

/// A salon's request to return products from a delivered order.
class ReturnRequest {
  final String id, code, salonId, orderId, orderCode;

  /// The original order's payment: a credit order's refund adjusts the
  /// outstanding balance; a cash order's is a voucher or a replacement.
  final bool cod;
  final String option, reason, note;
  final List<ReturnItem> items;

  /// Photo file ids (HOLA) or PhotoFiles names (on the device).
  final List<String> photos;
  String status;
  int? approvedAmount;
  ReturnProposal? proposal;
  ReturnPickup? pickup;
  ReturnSettlement? settlement;
  String? conversationId, rejectReason;
  final List<ReturnEvent> history;
  final DateTime createdAt;
  int version;

  ReturnRequest({
    required this.id,
    required this.code,
    required this.salonId,
    required this.orderId,
    required this.orderCode,
    required this.cod,
    required this.option,
    required this.reason,
    this.note = '',
    required this.items,
    List<String>? photos,
    required this.status,
    this.approvedAmount,
    this.proposal,
    this.pickup,
    this.settlement,
    this.conversationId,
    this.rejectReason,
    List<ReturnEvent>? history,
    required this.createdAt,
    this.version = 1,
  }) : photos = photos ?? [],
       history = history ?? [];

  int get amount => items.fold(0, (s, i) => s + i.total);
  int get units => items.fold(0, (s, i) => s + i.qty);
  bool get isOpen => ReturnStatus.open.contains(status);

  /// Money back on a credit order: "adjust in outstanding".
  bool get adjustsOutstanding => option == ReturnOption.refund && !cod;

  /// What the salon will get: a replacement (asked for, or HOLA's accepted
  /// offer), a voucher, or an outstanding adjustment.
  String get outcome {
    if (settlement != null) return settlement!.type;
    if (option == ReturnOption.replace) return SettlementType.replacement;
    if (!cod) return SettlementType.creditAdjusted;
    return proposal?.settlement == Settlement.replace ? SettlementType.replacement : SettlementType.voucher;
  }

  Json toJson() => {
    'id': id,
    'code': code,
    'salonId': salonId,
    'orderId': orderId,
    'orderCode': orderCode,
    'cod': cod,
    'option': option,
    'reason': reason,
    'note': note,
    'items': [for (final i in items) i.toJson()],
    'photos': photos,
    'status': status,
    'approvedAmount': approvedAmount,
    'proposal': proposal?.toJson(),
    'pickup': pickup?.toJson(),
    'settlement': settlement?.toJson(),
    'conversationId': conversationId,
    'rejectReason': rejectReason,
    'history': [for (final h in history) h.toJson()],
    'createdAt': iso(createdAt),
    'version': version,
  };

  factory ReturnRequest.fromJson(Json j) => ReturnRequest(
    id: j['id'],
    code: j['code'],
    salonId: j['salonId'],
    orderId: j['orderId'],
    orderCode: j['orderCode'] ?? '',
    cod: j['cod'] == true,
    option: j['option'],
    reason: j['reason'],
    note: j['note'] ?? '',
    items: objs(j['items'], ReturnItem.fromJson),
    photos: strs(j['photos']),
    status: j['status'],
    approvedAmount: j['approvedAmount'] == null ? null : asInt(j['approvedAmount']),
    proposal: j['proposal'] == null ? null : ReturnProposal.fromJson(Map<String, dynamic>.from(j['proposal'])),
    pickup: j['pickup'] == null ? null : ReturnPickup.fromJson(Map<String, dynamic>.from(j['pickup'])),
    settlement: j['settlement'] == null ? null : ReturnSettlement.fromJson(Map<String, dynamic>.from(j['settlement'])),
    conversationId: j['conversationId'],
    rejectReason: j['rejectReason'],
    history: objs(j['history'], ReturnEvent.fromJson),
    createdAt: dt(j['createdAt'])!,
    version: asInt(j['version'], 1),
  );
}

/// A pickup on a rider's list: which salon, which goods.
class ReturnPickupTask {
  final String returnId, code, salonName, salonPhone, address;
  final List<ReturnItem> items;
  final DateTime? expectedOn;
  const ReturnPickupTask({required this.returnId, required this.code, required this.salonName, this.salonPhone = '', this.address = '', required this.items, this.expectedOn});
  int get units => items.fold(0, (s, i) => s + i.qty);
}
