import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';

/// Where a delivery goes: the salon, its main branch and who to ask for.
class Stop {
  final Salon salon;
  final Branch? branch;
  final Account? owner;
  const Stop(this.salon, this.branch, this.owner);
  String get place => branch == null ? '' : [branch!.address, branch!.area].where((x) => x.isNotEmpty).join(', ');
}

/// The signed-in rider's deliveries, grouped by what they need to do next.
class DeliveriesViewModel extends RepoViewModel {
  DeliveriesViewModel(this._trade, this._salons, this._auth) : super(_trade);
  final TradeRepository _trade;
  final SalonRepository _salons;
  final AuthRepository _auth;

  String get _me => _auth.current?.id ?? '';
  List<TradeOrder> get _all => _trade.ordersForRider(_me);

  List<TradeOrder> get outForDelivery => _all.where((o) => o.status == OrderStatus.outForDelivery).toList();
  List<TradeOrder> get assigned => _all.where((o) => o.status == OrderStatus.dispatched).toList();
  List<TradeOrder> get failed => _all.where((o) => o.status == OrderStatus.failed).toList();

  /// Delivered in the last 7 days, newest first.
  List<TradeOrder> get delivered {
    final since = addDays(today, -7);
    return _all.where((o) => (o.status == OrderStatus.delivered || o.status == OrderStatus.confirmed) && !(o.at(OrderStatus.delivered) ?? o.createdAt).isBefore(since)).toList()
      ..sort((a, b) => (b.at(OrderStatus.delivered) ?? b.createdAt).compareTo(a.at(OrderStatus.delivered) ?? a.createdAt));
  }

  bool get isEmpty => _all.isEmpty;
  int get toDeliver => outForDelivery.length + assigned.length;
  int get deliveredToday => _all.where((o) => sameDay(o.at(OrderStatus.delivered) ?? DateTime(0), now())).length;
  int get cashToCollect => [...outForDelivery, ...assigned].where((o) => o.isCod).fold(0, (t, o) => t + o.total);

  Stop stop(TradeOrder o) {
    final s = _salons.salon(o.salonId)!;
    final bs = _salons.branches(s.id);
    return Stop(s, bs.isEmpty ? null : bs.first, _auth.account(s.ownerId));
  }
}
