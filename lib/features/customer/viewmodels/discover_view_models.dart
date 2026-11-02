import '../../../core/l10n/l10n.dart';
import '../../../core/mvvm/repo_view_model.dart';
import '../../../core/utils/clock.dart';
import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import 'customer_lookups.dart';

/// Home tab: next visit, favourites, salons to discover, a visit to review.
class HomeViewModel extends RepoViewModel with CustomerLookups {
  HomeViewModel(this.salons, this.bookings, this.auth) : super(salons);
  @override
  final SalonRepository salons;
  @override
  final AuthRepository auth;
  final BookingRepository bookings;

  List<Appointment> get _mine => me == null ? const [] : bookings.forCustomer(me!.id);

  Appointment? get nextVisit => _mine.where((a) => ApptStatus.upcoming.contains(a.status) && a.endsAt.isAfter(now())).firstOrNull;

  Appointment? get toReview => _mine.reversed.where((a) => a.status == ApptStatus.completed && !a.reviewed).firstOrNull;

  List<Salon> get favourites => [for (final id in me?.favourites ?? const <String>[]) ?salons.salon(id)].where((s) => s.isListed).toList();

  List<Salon> get live => salons.discover();

  /// Salons in the customer's city first (if they set one).
  List<Salon> get nearYou {
    final city = me?.city.trim() ?? '';
    if (city.isEmpty) return const [];
    return salons.discover(city: city);
  }

  List<Salon> get topRated => live.where((s) => salons.rating(s.id).count > 0).take(5).toList();

  List<Salon> get newest => ([...live]..sort((a, b) => b.createdAt.compareTo(a.createdAt))).take(6).toList();

  String get greeting {
    final h = now().hour;
    return h < 12 ? tr('Good morning') : h < 17 ? tr('Good afternoon') : tr('Good evening');
  }
}

/// Explore tab: search, category and city filters over live salons.
class ExploreViewModel extends RepoViewModel with CustomerLookups {
  ExploreViewModel(this.salons, this.auth) : super(salons) {
    category = exploreIntent.category;
    exploreIntent.addListener(_intent);
  }
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

  List<Salon> get results => salons.discover(query: query, category: category, city: city);

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
