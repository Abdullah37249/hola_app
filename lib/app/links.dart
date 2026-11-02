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
  final salonSide = role == Role.salonOwner || role == Role.salonStaff;
  final Widget? page = switch (link.type) {
    'appointment' => role == Role.customer ? BookingDetailPage(id: link.id) : salonSide ? AppointmentDetailPage(id: link.id) : null,
    'order' => switch (role) { Role.rider => DeliveryPage(id: link.id), Role.salonOwner || Role.salesOfficer => OrderDetailPage(id: link.id), _ => null },
    'salon' => role == Role.salesOfficer ? SalonRecordPage(id: link.id) : role == Role.salonOwner ? const SalonProfilePage() : null,
    'training' => role == Role.salesOfficer ? TrainingAdminPage(id: link.id) : salonSide ? TrainingPage(id: link.id) : null,
    'review' => salonSide
        ? const ReviewsPage()
        : _customerReview(context, link.id),
    'complaint' => salonSide ? const FeedbackInboxPage() : const MyFeedbackPage(),
    'chat' => ChatPage(threadId: link.id, asSalon: salonSide),
    'leave' => role == Role.salonOwner ? const LeaveRequestsPage() : role == Role.salonStaff ? const MyLeavePage() : null,
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
