import '../../../core/mvvm/repo_view_model.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import 'customer_lookups.dart';

/// Salon page: branch picker, menu selection, team, reviews.
class SalonViewModel extends RepoViewModel with CustomerLookups {
  SalonViewModel(this.salons, this.auth, this.engage, this.id, {String? select}) : super(salons) {
    branchId = salons.branches(id).firstOrNull?.id;
    engage.syncSalonReviews(id); // published reviews and their photos, from HOLA
    if (select != null && salons.service(select)?.active == true) selected.add(select);
  }
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final EngagementRepository engage;
  final String id;

  String? branchId;
  String tab = 'svc';
  final selected = <String>{};

  Salon? get s => salons.salon(id);
  List<Branch> get branches => salons.branches(id);
  Branch? get currentBranch => branchId == null ? null : salons.branch(branchId!) ?? branches.firstOrNull;
  SalonRating get rating => salons.rating(id);
  bool get favourite => salons.isFavourite(id);
  bool get bookable => s?.isListed ?? false;

  /// Active services grouped by category, in category order.
  List<(String, List<ServiceItem>)> get menu {
    final all = salons.services(id, activeOnly: true);
    return [
      for (final c in serviceCategories)
        if (all.any((x) => x.category == c)) (c, all.where((x) => x.category == c).toList()),
    ];
  }

  List<ServiceItem> get chosen => [for (final x in selected) ?salons.service(x)];
  int get total => chosen.fold(0, (t, x) => t + priceAfterOffer(x));
  int get minutes => chosen.fold(0, (t, x) => t + x.durationMin);

  /// This salon's running offers, by service.
  Map<String, ServiceOffer> get offersByService => {for (final o in offersLive(salonId: id)) o.serviceId: o};

  List<Review> get reviews => engage.reviewsForSalon(id);
  List<(StaffProfile, String)> get pros => team(id, branchId: branchId);

  @override
  void refresh() {
    selected.removeWhere((x) => salons.service(x)?.active != true);
    if (branchId != null && salons.branch(branchId!) == null) branchId = branches.firstOrNull?.id;
  }

  void setBranch(String b) {
    branchId = b;
    notify();
  }

  void setTab(String t) {
    tab = t;
    notify();
  }

  void toggle(String serviceId) {
    if (!selected.remove(serviceId)) selected.add(serviceId);
    notify();
  }

  Future<bool> toggleFavourite() => salons.toggleFavourite(id);
}
