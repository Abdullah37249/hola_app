import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../domain/entities/entities.dart';
import '../domain/repositories/repositories.dart';
import '../features/chat/chat.dart';
import '../features/customer/customer.dart';
import '../features/field/field.dart';
import '../features/rider/rider.dart';
import '../features/salon/salon.dart';
import '../features/trade/trade.dart';
import '../shared/widgets/fx.dart';
import 'viewmodels/session_view_model.dart';

/// Opens the screen a notification points at, for the signed-in role.
void openLink(BuildContext context, NotifLink link) {
  final role = context.read<SessionViewModel>().account?.role;
  // A salon paying this rider: the card is on the Deliveries home.
  if ((link.type == 'collection' || link.type == 'return') && role == Role.rider) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    context.read<SessionViewModel>().setTab('today');
    return;
  }
  final salonSide = role == Role.salonOwner || role == Role.salonStaff;
  final Widget? page = switch (link.type) {
    'appointment' =>
      role == Role.customer
          ? BookingDetailPage(id: link.id)
          : salonSide
          ? AppointmentDetailPage(id: link.id)
          : null,
    'order' => switch (role) {
      Role.rider => DeliveryPage(id: link.id),
      Role.salonOwner || Role.salesOfficer => OrderDetailPage(id: link.id),
      _ => null,
    },
    'salon' =>
      role == Role.salesOfficer
          ? SalonRecordPage(id: link.id)
          : role == Role.salonOwner
          ? const SalonProfilePage()
          : null,
    'training' =>
      role == Role.salesOfficer || role == Role.trainer
          ? TrainingAdminPage(id: link.id)
          : salonSide
          ? TrainingPage(id: link.id)
          : null,
    'review' => salonSide ? const ReviewsPage() : _customerReview(context, link.id),
    // Complaints were switched off on HOLA (0.30.0): an old push opens nothing.
    'complaint' when context.read<EngagementRepository>().complaintsOn => salonSide ? const FeedbackInboxPage() : const MyFeedbackPage(),
    'chat' => ChatPage(threadId: link.id),
    'return' => role == Role.salonOwner || role == Role.salesOfficer ? ReturnDetailPage(id: link.id) : null,
    'leave' => role == Role.salonOwner ? const LeaveRequestsPage() : null,
    // A coupon HOLA sent the salon → its offers.
    'offers' => switch (context.read<SessionViewModel>().account?.salonId) {
      final id? when salonSide => OffersPage(salonId: id),
      _ => null,
    },
    // A salon's offer on a service is free to use again → the customer's offers.
    'service_offer' => salonSide ? null : const CustomerOffersPage(),
    // A credit payment confirmed, rejected or collected → the salon's statement.
    'payment' => switch (context.read<SessionViewModel>().account?.salonId) {
      final id? when salonSide => StatementPage(salonId: id),
      _ => null,
    },
    _ => null,
  };
  if (page != null) pushPage(context, page);
}

Widget? _customerReview(BuildContext context, String reviewId) {
  final booking = context.read<BookingRepository>();
  final me = context.read<SessionViewModel>().account;
  if (me == null) return null;
  // A review reply → the booking it was written for.
  for (final a in booking.forCustomer(me.id)) {
    if (context.read<EngagementRepository>().reviewForAppointment(a.id)?.id == reviewId) return BookingDetailPage(id: a.id);
  }
  return null;
}
