import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../core/utils/location.dart';
import 'customer_lookups.dart';

/// Home tab: next visit, favourites, salons to discover, a visit to review.
class HomeViewModel extends RepoViewModel with CustomerLookups {
  HomeViewModel(this.salons, this.bookings, this.auth, this.engage) : super(salons) {
    salons.syncDirectory(); // HOLA's live salons
  }

  Future<void> syncSalons() => salons.syncDirectory();
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final BookingRepository bookings;
  final EngagementRepository engage;

  /// Rates a finished visit; the "How was…?" card then goes away.
  Future<void> addReview(String appointmentId, int stars, String text, List<(String, String)> photos) => engage.addReview(appointmentId: appointmentId, stars: stars, text: text, photos: photos);

  List<Appointment> get _mine => me == null ? const [] : bookings.forCustomer(me!.id);

  Appointment? get nextVisit => _mine.where((a) => ApptStatus.upcoming.contains(a.status) && a.endsAt.isAfter(now())).firstOrNull;

  Appointment? get toReview => _mine.reversed.where((a) => a.status == ApptStatus.completed && !a.reviewed).firstOrNull;

  List<Salon> get favourites => [for (final id in me?.favourites ?? const <String>[]) ?salons.salon(id)].where((s) => s.isListed).toList();

  List<Salon> get live => salons.discover();

  /// Running offers at the salons this customer can see.
  List<ServiceOffer> get offers => offersLive();

  /// Salons in the customer's city first (if they set one).
  List<Salon> get nearYou {
    final city = me?.city.trim() ?? '';
    if (city.isEmpty) return const [];
    return salons.discover(city: city);
  }

  /// Highest rated first (more reviews break a tie); salons without reviews
  /// yet follow, so the list is there from day one.
  List<Salon> get topRated {
    final xs = [...live];
    int byRating(Salon a, Salon b) {
      final ra = salons.rating(a.id), rb = salons.rating(b.id);
      final r = rb.average.compareTo(ra.average);
      return r != 0 ? r : rb.count.compareTo(ra.count);
    }

    return (xs..sort(byRating)).take(5).toList();
  }

  List<Salon> get newest => ([...live]..sort((a, b) => b.createdAt.compareTo(a.createdAt))).take(6).toList();

  String get greeting {
    final h = now().hour;
    return h < 12
        ? tr('Good morning')
        : h < 17
        ? tr('Good afternoon')
        : tr('Good evening');
  }
}

/// Explore tab: search, category and city filters over live salons.
class ExploreViewModel extends RepoViewModel with CustomerLookups {
  ExploreViewModel(this.salons, this.auth) : super(salons) {
    salons.syncDirectory(); // HOLA's live salons
    category = exploreIntent.category;
    exploreIntent.addListener(_intent);
  }

  Future<void> syncSalons() => salons.syncDirectory();
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;

  String query = '';
  String? category;
  String? city;

  void _intent() {
    category = exploreIntent.category;
    notify();
  }

  List<Salon> get results {
    final xs = salons.discover(query: query, category: category, city: city);
    if (!nearFirst || here == null) return xs;
    // Nearest first; salons without a location on the map go last.
    double key(Salon s) => distanceTo(s) ?? double.infinity;
    return xs..sort((a, b) => key(a).compareTo(key(b)));
  }

  // ── near me ──

  /// The phone's position, once the customer asked for salons near them.
  GeoFix? here;
  bool nearFirst = false, locating = false, showMap = false;

  /// Kilometres to the salon's nearest branch with a location (null if none).
  double? distanceTo(Salon s) {
    final h = here;
    if (h == null) return null;
    double? best;
    for (final b in salons.branches(s.id)) {
      final at = b.location;
      if (at == null) continue;
      final d = distanceKm(h, at);
      if (best == null || d < best) best = d;
    }
    return best;
  }

  /// Branches of [list] that can be put on the map.
  List<(Salon, Branch)> pins(List<Salon> list) => [
    for (final s in list)
      for (final b in salons.branches(s.id))
        if (b.location != null) (s, b),
  ];

  /// Sorts by distance, asking for the phone's location the first time.
  /// Returns false when the location can't be read (off or refused).
  Future<bool> toggleNearMe() async {
    if (nearFirst) {
      nearFirst = false;
      notify();
      return true;
    }
    if (!await locate()) return false;
    nearFirst = true;
    notify();
    return true;
  }

  /// Reads the phone's location (again). False when it can't.
  Future<bool> locate() async {
    locating = true;
    notify();
    final fix = await Location.read();
    locating = false;
    if (fix != null) here = fix;
    notify();
    return fix != null;
  }

  void toggleMap() {
    showMap = !showMap;
    notify();
  }

  /// Cities that have at least one live salon.
  List<String> get cities {
    final set = <String>{};
    for (final s in salons.discover()) {
      for (final b in salons.branches(s.id)) {
        if (b.city.trim().isNotEmpty) set.add(b.city.trim());
      }
    }
    return set.toList()..sort();
  }

  bool get filtered => query.trim().isNotEmpty || category != null || city != null;

  void setQuery(String q) {
    query = q;
    notify();
  }

  void setCategory(String? c) {
    category = category == c ? null : c;
    exploreIntent.category = category;
    notify();
  }

  void setCity(String? c) {
    city = city == c ? null : c;
    notify();
  }

  void clear() {
    query = '';
    category = null;
    city = null;
    exploreIntent.category = null;
    notify();
  }

  @override
  void dispose() {
    exploreIntent.removeListener(_intent);
    super.dispose();
  }
}

/// Saved salons list.
class SavedViewModel extends RepoViewModel with CustomerLookups {
  SavedViewModel(this.salons, this.auth) : super(salons);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;

  List<Salon> get saved => [for (final id in me?.favourites ?? const <String>[]) ?salons.salon(id)];

  Future<void> remove(String id) => salons.toggleFavourite(id);
}
