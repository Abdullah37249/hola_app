import '../../core/utils/clock.dart';
import '../../domain/entities/entities.dart';
import 'local_database.dart';

// The once-per-customer rules for salon offers (HOLA contract 0.20.0), shared
// by the salon list and booking: an open booking holds the offer, a completed
// or no-show one spends it, and a cancelled or declined one frees it again.

/// Booking statuses that spend an offer for good.
const offerSpent = {ApptStatus.completed, ApptStatus.noShow};

/// [customerId]'s bookings that carry [o].
Iterable<Appointment> bookingsWithOffer(LocalDatabase db, String? customerId, ServiceOffer o) =>
    customerId == null ? const [] : db.appointments.where((a) => a.customerId == customerId && a.offerIds.contains(o.id));

/// [OfferUse] of [o] for [customerId].
String offerUseOf(LocalDatabase db, String? customerId, ServiceOffer o) {
  final mine = bookingsWithOffer(db, customerId, o);
  // A booking this phone just made counts before the server reports it.
  if (o.myUse == OfferUse.used || mine.any((a) => offerSpent.contains(a.status))) return OfferUse.used;
  if (mine.any((a) => ApptStatus.holding.contains(a.status))) return OfferUse.reserved;
  // Cancelled here since the last sync: free again.
  if (o.myUse == OfferUse.reserved && mine.isNotEmpty && mine.every((a) => ApptStatus.finished.contains(a.status))) return OfferUse.none;
  return o.myUse;
}

/// The code of the open booking holding [o] for [customerId], or ''.
String heldOnOf(LocalDatabase db, String? customerId, ServiceOffer o) => bookingsWithOffer(db, customerId, o).where((a) => ApptStatus.holding.contains(a.status)).firstOrNull?.code ?? o.heldOn;

/// The biggest running offer on [svc] that [customerId] can still use.
ServiceOffer? bestOfferOn(LocalDatabase db, String? customerId, ServiceItem svc) {
  if (!svc.active) return null;
  final t = now();
  final xs = db.offers.where((o) => o.serviceId == svc.id && o.liveAt(t) && offerUseOf(db, customerId, o) == OfferUse.none).toList()
    ..sort((a, b) => b.discountOn(svc.price).compareTo(a.discountOn(svc.price)));
  return xs.firstOrNull;
}
