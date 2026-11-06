import 'package:provider/provider.dart';

import '../core/network/api.dart';
import 'package:provider/single_child_widget.dart';

import '../data/local/local_auth_repository.dart';
import '../data/local/local_booking_repository.dart';
import '../data/local/local_chat_repository.dart';
import '../data/local/local_database.dart';
import '../data/local/local_engagement_repository.dart';
import '../data/local/local_field_repository.dart';
import '../data/local/local_preferences_repository.dart';
import '../data/local/local_return_repository.dart';
import '../data/local/local_salon_repository.dart';
import '../data/local/local_trade_repository.dart';
import '../data/local/storage.dart';
import '../domain/repositories/repositories.dart';
import 'viewmodels/session_view_model.dart';

/// Composition root. The only place that knows repositories are on-device;
/// swap these for API-backed implementations to connect the HOLA backend.
///
/// [api] connects sign-in, customer sign-up and the salon directory to the
/// HOLA server; without it (widget tests) everything stays on the device.
List<SingleChildWidget> appProviders({Storage? storage, HolaApi? api}) {
  final db = LocalDatabase(storage ?? FileStorage());
  return [
    Provider<AuthRepository>.value(value: LocalAuthRepository(db, api: api)),
    Provider<SalonRepository>.value(value: LocalSalonRepository(db, api: api)),
    Provider<BookingRepository>.value(value: LocalBookingRepository(db, api: api)),
    Provider<EngagementRepository>.value(value: LocalEngagementRepository(db, api: api)),
    Provider<ChatRepository>.value(value: LocalChatRepository(db, api: api)),
    Provider<TradeRepository>.value(value: LocalTradeRepository(db, api: api)),
    Provider<ReturnRepository>.value(value: LocalReturnRepository(db, api: api)),
    Provider<FieldRepository>.value(value: LocalFieldRepository(db, api: api)),
    Provider<PreferencesRepository>.value(value: LocalPreferencesRepository(db)),
    ChangeNotifierProvider(create: (c) => SessionViewModel(c.read<AuthRepository>(), c.read<PreferencesRepository>())..init()),
  ];
}
