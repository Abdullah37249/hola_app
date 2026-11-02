import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';

/// Cash the rider holds from COD deliveries, and their handovers to HOLA.
class CashViewModel extends RepoViewModel {
  CashViewModel(this._trade, this._salons, this._auth) : super(_trade);
  final TradeRepository _trade;
  final SalonRepository _salons;
  final AuthRepository _auth;

  String get _me => _auth.current?.id ?? '';
  List<TradeOrder> get inHand => _trade.cashOnHand(_me);
  int get total => inHand.fold(0, (t, o) => t + (o.cashCollected ?? 0));
  List<CashHandover> get history => _trade.handovers(riderId: _me);

  String salonName(String salonId) => _salons.salon(salonId)?.name ?? tr('Salon');
  String? confirmedBy(CashHandover h) => h.confirmedById == null ? null : _auth.account(h.confirmedById!)?.name;

  Future<void> handOver() => _trade.handOverCash();
}
