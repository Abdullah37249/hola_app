import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';

/// Cash the rider holds from COD deliveries, and their handovers to HOLA.
class CashViewModel extends RepoViewModel {
  CashViewModel(this._trade, this._salons, this._auth) : super(_trade) {
    _trade.syncCash();
  }

  /// Pull-to-refresh (the office may have received the cash meanwhile).
  Future<void> pull() => _trade.syncCash();
  final TradeRepository _trade;
  final SalonRepository _salons;
  final AuthRepository _auth;

  String get _me => _auth.current?.id ?? '';
  List<CashPayment> get inHand => _trade.cashHeld(_me);
  int get total => inHand.fold(0, (t, p) => t + p.amount);

  /// The salon an order code was delivered to, when the phone knows it.
  String salonFor(String orderCode) {
    final o = _trade.ordersForRider(_me).where((o) => o.code == orderCode).firstOrNull;
    return o == null ? '' : salonName(o.salonId);
  }

  List<CashHandover> get history => _trade.handovers(riderId: _me);

  String salonName(String salonId) => _salons.salon(salonId)?.name ?? tr('Salon');
  String? confirmedBy(CashHandover h) => h.confirmedById == null ? null : _auth.account(h.confirmedById!)?.name;

  Future<void> handOver() => _trade.handOverCash();
}
