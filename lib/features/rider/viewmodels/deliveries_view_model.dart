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

  /// Street, area and city: everything a rider needs to find the salon.
  String get fullAddress => branch == null ? '' : [branch!.address, branch!.area, branch!.city].where((x) => x.trim().isNotEmpty).join(', ');

  /// GPS captured at the salon's door, when the salon saved one.
  GeoFix? get location => branch?.location;

  /// The owner's name and number: the account on this phone, else what HOLA sent.
  String get ownerName => (owner?.name.isNotEmpty ?? false) ? owner!.name : salon.ownerName ?? '';
  String get ownerPhone => (owner?.phone.isNotEmpty ?? false) ? owner!.phone : salon.ownerPhone ?? '';

  /// HOLA's directions link for this address, if it sent one.
  String? get mapsUrl => branch?.mapsUrl;

  /// Who to call: the owner's number, else the salon's.
  String get phone => ownerPhone.isNotEmpty ? ownerPhone : salon.phone;
}

/// The signed-in rider's deliveries, grouped by what they need to do next.
class DeliveriesViewModel extends RepoViewModel {
  DeliveriesViewModel(this._trade, this._salons, this._auth, {ReturnRepository? returns}) : _returns = returns, super(_trade) {
    _trade.syncDeliveries();
    _trade.syncCollections();
    if (_returns != null) Future.microtask(_returns.syncPickups);
  }
  final ReturnRepository? _returns;

  /// Returned goods HOLA sent this rider to collect from salons.
  List<ReturnPickupTask> get pickups => _returns?.pickups() ?? const [];
  Future<void> collectPickup(ReturnPickupTask p) => _returns!.collectPickup(p.returnId);

  /// Salons that chose this rider to hand their HOLA payment to.
  List<CollectionRequest> get collections => _trade.collections();
  Future<void> confirmCollection(CollectionRequest c, int amount) => _trade.confirmCollection(c.id, amount);
  Future<void> declineCollection(CollectionRequest c, String reason) => _trade.declineCollection(c.id, reason);

  /// A credit payment the salon hands over with this delivery, if any.
  CreditCollection? collectFor(TradeOrder o) => o.status == OrderStatus.dispatched || o.status == OrderStatus.outForDelivery ? _trade.creditCollectionFor(o.id) : null;

  /// Pull-to-refresh: fetch the latest assignments from HOLA.
  Future<void> pull() => Future.wait([_trade.syncDeliveries(), _trade.syncCollections(), if (_returns != null) _returns.syncPickups()]);
  final TradeRepository _trade;
  final SalonRepository _salons;
  final AuthRepository _auth;

  String get _me => _auth.current?.id ?? '';

  /// The rider's first name, for the greeting.
  String get firstName => _auth.current?.firstName ?? '';
  List<TradeOrder> get _all => _trade.ordersForRider(_me);

  List<TradeOrder> get outForDelivery => _all.where((o) => o.status == OrderStatus.outForDelivery).toList();
  List<TradeOrder> get assigned => _all.where((o) => o.status == OrderStatus.dispatched).toList();
  List<TradeOrder> get failed => _all.where((o) => o.status == OrderStatus.failed).toList();

  /// Delivered (last 7 days) and failed: the "Done" list.
  List<TradeOrder> get done => [...failed, ...delivered];

  /// The rider has the order in hand and is leaving: out for delivery.
  Future<void> pickUp(TradeOrder o) => _trade.startDelivery(o.id);

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
