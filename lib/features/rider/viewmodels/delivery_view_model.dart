import 'package:flutter/painting.dart';

import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/utils/location.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import 'deliveries_view_model.dart';

/// One delivery: details, next action, and proof of delivery capture.
class DeliveryViewModel extends RepoViewModel {
  DeliveryViewModel(this.id, this._trade, this._salons, this._auth) : super(_trade) {
    recipient = stop?.owner?.name ?? '';
  }
  final String id;
  final TradeRepository _trade;
  final SalonRepository _salons;
  final AuthRepository _auth;

  TradeOrder? get order => _trade.order(id);
  Stop? get stop {
    final o = order;
    if (o == null) return null;
    final s = _salons.salon(o.salonId);
    if (s == null) return null;
    final bs = _salons.branches(s.id);
    return Stop(s, bs.isEmpty ? null : bs.first, _auth.account(s.ownerId));
  }

  /// A credit payment the salon hands over with this delivery, if any.
  CreditCollection? get creditCollection {
    final o = order;
    if (o == null || !{OrderStatus.dispatched, OrderStatus.outForDelivery}.contains(o.status)) return null;
    return _trade.creditCollectionFor(id);
  }

  Future<void> collectCredit(int amount) => _trade.collectCredit(creditCollection!.requestId, amount);

  // ── actions ──
  Future<void> start() => _trade.startDelivery(id);
  Future<void> fail(String reason) => _trade.failDelivery(id, reason);

  // ── proof of delivery ──
  /// HOLA wants a photo of the handover for its orders.
  bool get needsPhoto => _trade.needsDeliveryPhoto(id);
  String? photo; // local file of the photo taken

  void setPhoto(String path) {
    photo = path;
    notify();
  }

  String recipient = '';
  String cash = '';

  /// Strokes in the pad's unit square (0..1), as stored on the order.
  final List<List<Offset>> strokes = [];

  bool get signed => strokes.any((s) => s.length > 1);

  void setRecipient(String v) {
    recipient = v;
    notify();
  }

  void setCash(String v) {
    cash = v;
    notify();
  }

  void strokeStart(Offset p) {
    strokes.add([p]);
    notify();
  }

  void strokeUpdate(Offset p) {
    if (strokes.isEmpty) return;
    strokes.last.add(p);
    notify();
  }

  void clearSignature() {
    strokes.clear();
    notify();
  }

  int? get cashValue => int.tryParse(cash.replaceAll(RegExp(r'[^0-9]'), ''));

  /// Hands the order over, recording where (GPS) when the phone can.
  Future<void> deliver() async => _trade.deliver(
    id,
    recipientName: recipient,
    signature: [
      for (final s in strokes) [for (final p in s) (p.dx, p.dy)],
    ],
    cashCollected: order!.isCod ? cashValue : null,
    where: await Location.read(),
    photoPath: photo,
  );
}
