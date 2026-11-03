import 'package:flutter/widgets.dart';

import '../features/customer/customer.dart';
import '../features/field/field.dart';
import '../features/rider/rider.dart';
import '../features/salon/salon.dart';
import '../features/trade/trade.dart';

class TabDef {
  final String id, label, icon;
  final Widget Function() build;
  const TabDef(this.id, this.label, this.icon, this.build);
}

/// Tab bars per experience (keyed by SessionViewModel.rk).
final Map<String, List<TabDef>> tabsFor = {
  'customer': [
    TabDef('home', 'Home', 'home', () => const CustomerHome()),
    TabDef('explore', 'Explore', 'search', () => const CustomerExplore()),
    TabDef('bookings', 'Bookings', 'cal', () => const CustomerBookings()),
    TabDef('profile', 'Profile', 'user', () => const CustomerProfile()),
  ],
  'salon': [
    TabDef('today', 'Today', 'home', () => const SalonToday()),
    TabDef('calendar', 'Calendar', 'cal', () => const SalonCalendar()),
    TabDef('products', 'Products', 'box', () => const SalonProductsTab()),
    TabDef('training', 'Training', 'grad', () => const SalonTrainingTab()),
    TabDef('more', 'More', 'grid', () => const SalonMore()),
  ],
  'field': [
    TabDef('today', 'Today', 'home', () => const FieldToday()),
    TabDef('salons', 'Salons', 'store', () => const FieldSalons()),
    TabDef('visits', 'Visits', 'pin', () => const FieldVisits()),
    TabDef('orders', 'Orders', 'box', () => const FieldOrders()),
    TabDef('more', 'More', 'grid', () => const FieldMore()),
  ],
  'trainer': [TabDef('training', 'Training', 'grad', () => const TrainerHome()), TabDef('more', 'More', 'grid', () => const TrainerMore())],
  'rider': [TabDef('today', 'Deliveries', 'truck', () => const RiderToday()), TabDef('cash', 'Cash', 'cash', () => const RiderCash()), TabDef('more', 'More', 'grid', () => const RiderMore())],
};
