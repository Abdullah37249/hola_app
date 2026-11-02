import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../data/local/local_auth_repository.dart';
import '../data/local/local_booking_repository.dart';
import '../data/local/local_database.dart';
import '../data/local/local_engagement_repository.dart';
import '../data/local/local_field_repository.dart';
import '../data/local/local_preferences_repository.dart';
import '../data/local/local_salon_repository.dart';
import '../data/local/local_trade_repository.dart';
import '../data/local/storage.dart';
import '../domain/repositories/repositories.dart';
import 'viewmodels/session_view_model.dart';

/// Composition root. The only place that knows repositories are on-device;
/// swap these for API-backed implementations to connect the HOLA backend.
List<SingleChildWidget> appProviders({Storage? storage}) {
  final db = LocalDatabase(storage ?? FileStorage());
  return [
    Provider<AuthRepository>.value(value: LocalAuthRepository(db)),
    Provider<SalonRepository>.value(value: LocalSalonRepository(db)),
    Provider<BookingRepository>.value(value: LocalBookingRepository(db)),
    Provider<EngagementRepository>.value(value: LocalEngagementRepository(db)),
    Provider<TradeRepository>.value(value: LocalTradeRepository(db)),
    Provider<FieldRepository>.value(value: LocalFieldRepository(db)),
    Provider<PreferencesRepository>.value(value: LocalPreferencesRepository(db)),
    ChangeNotifierProvider(create: (c) => SessionViewModel(c.read<AuthRepository>(), c.read<PreferencesRepository>())..init()),
  ];
}
