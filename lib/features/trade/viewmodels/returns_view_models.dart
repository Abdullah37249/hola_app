import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';

/// A status in words and a badge tone.
(String, String) returnStatusLabel(String status) => switch (status) {
  ReturnStatus.requested => (tr('Return requested'), 'info'),
  ReturnStatus.underReview => (tr('Under review'), 'info'),
  ReturnStatus.responseSent => (tr('HOLA replied'), 'warn'),
  ReturnStatus.awaitingSalon => (tr('Your answer needed'), 'warn'),
  ReturnStatus.approved => (tr('Approved'), 'ok'),
  ReturnStatus.pickupAssigned => (tr('Pickup assigned'), 'info'),
  ReturnStatus.rejected => (tr('Rejected'), 'bad'),
  ReturnStatus.replacementCreated => (tr('Replacement on its way'), 'ok'),
  ReturnStatus.completed => (tr('Completed'), 'ok'),
  ReturnStatus.cancelled => (tr('Withdrawn'), 'mute'),
  _ => (status, 'mute'),
};

/// "Replace product" / "Adjust in outstanding" / "Cash refund / voucher".
String returnOptionLabel(String option, {required bool cod}) => option == ReturnOption.replace
    ? tr('Replace product')
    : cod
    ? tr('Cash refund / voucher')
    : tr('Adjust in outstanding');

/// The salon's return requests (HOLA's team: every salon's).
class ReturnsViewModel extends RepoViewModel {
  ReturnsViewModel(this.returns, {this.salonId}) : super(returns) {
    // After the first frame: a sync may change data the screen is building from.
    Future.microtask(returns.syncReturns);
  }
  final ReturnRepository returns;
  final String? salonId;

  List<ReturnRequest> get all => returns.returns(salonId: salonId);
  List<ReturnRequest> get open => all.where((r) => r.isOpen).toList();
  List<ReturnRequest> get closed => all.where((r) => !r.isOpen).toList();

  Future<void> reload() => returns.syncReturns();
}

/// One return, with what the signed-in side may do.
class ReturnDetailViewModel extends RepoViewModel {
  ReturnDetailViewModel(this.returns, this.trade, this.auth, this.id) : super(returns) {
    Future.microtask(() => returns.syncReturn(id));
  }
  final ReturnRepository returns;
  final TradeRepository trade;
  final AuthRepository auth;
  final String id;

  ReturnRequest? get r => returns.returnRequest(id);
  TradeOrder? get order => r == null ? null : trade.order(r!.orderId);
  TradeOrder? get replacement => r?.settlement?.replacementOrderId == null ? null : trade.order(r!.settlement!.replacementOrderId!);
  List<Account> get riders => auth.accountsWithRole(Role.rider);
  bool get isOwner => auth.current?.role == Role.salonOwner;
  bool get isHola => auth.current?.role == Role.salesOfficer;

  bool get canCancel => isOwner && r != null && ReturnStatus.cancellable.contains(r!.status);
  bool get canAnswer => isOwner && r?.status == ReturnStatus.awaitingSalon && r?.proposal != null;
  bool get _undecided => r != null && ReturnStatus.undecided.contains(r!.status);
  bool get canReview => isHola && r?.status == ReturnStatus.requested;
  bool get canRespond => isHola && _undecided;
  bool get canAssignPickup => isHola && r?.status == ReturnStatus.approved;
  bool get canApprove => isHola && _undecided && !(r!.cod && r!.option == ReturnOption.refund);
  bool get canPropose => isHola && _undecided && r!.cod && r!.option == ReturnOption.refund;
  bool get canReject => isHola && (_undecided || r?.status == ReturnStatus.awaitingSalon);

  Future<void> cancel() => returns.cancelReturn(id);
  Future<void> accept() => returns.acceptProposal(id);
  Future<void> decline(String note) => returns.declineProposal(id, note);
  Future<void> review() => returns.startReview(id);
  Future<void> approve() => returns.approveReturn(id);
  Future<void> reject(String reason) => returns.rejectReturn(id, reason);
  Future<void> respond(String note) => returns.respond(id, note);
  Future<void> propose(String settlement) => returns.proposeSettlement(id, settlement: settlement);
  Future<void> assignPickup(String riderId) => returns.assignPickup(id, riderId);
}

/// Filling in a return for one delivered order.
class NewReturnViewModel extends RepoViewModel {
  NewReturnViewModel(this.returns, this.trade, this.orderId) : super(returns);
  final ReturnRepository returns;
  final TradeRepository trade;
  final String orderId;

  TradeOrder? get order => trade.order(orderId);
  String option = ReturnOption.replace;
  String? reason;
  final qty = <String, int>{};

  int left(OrderLine l) => order == null ? 0 : returns.returnable(order!, l.variantId);
  int qtyOf(String variantId) => qty[variantId] ?? 0;

  void setQty(OrderLine l, int n) {
    qty[l.variantId] = n.clamp(0, left(l));
    notifyListeners();
  }

  void setOption(String o) {
    option = o;
    notifyListeners();
  }

  void setReason(String r) {
    reason = r;
    notifyListeners();
  }

  /// What the picked units are worth (the order's price after its coupon).
  int get value {
    final o = order;
    if (o == null || o.subtotal == 0) return 0;
    var v = 0;
    for (final l in o.lines) {
      v += qtyOf(l.variantId) * returns.unitValue(o, l.variantId);
    }
    return v;
  }

  int get units => qty.values.fold(0, (s, n) => s + n);

  /// Photos of the problem (paths on this phone), up to 6.
  final photos = <String>[];

  void setPhotos(List<String> ps) {
    photos
      ..clear()
      ..addAll(ps);
    notifyListeners();
  }

  Future<ReturnRequest> submit(String note) => returns.requestReturn(orderId: orderId, option: option, reason: reason ?? '', note: note, qty: qty, photoPaths: photos);
}
