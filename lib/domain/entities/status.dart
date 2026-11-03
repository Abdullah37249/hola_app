import '../../core/l10n/l10n.dart';

// Status vocabulary (shared with the HOLA API) → how it reads in the app.

/// Status → (label, tone ok|warn|bad|info|mute, live).
/// Labels follow the app language, so this is rebuilt on each read.
Map<String, (String, String, bool)> get statusLabels => {
  // Appointments
  'REQUESTED': (tr('Waiting for salon'), 'warn', false), 'CONFIRMED': (tr('Confirmed'), 'info', false), 'DECLINED': (tr('Declined'), 'bad', false),
  'CHECKED_IN': (tr('Checked in'), 'info', false), 'IN_SERVICE': (tr('In service'), 'info', true), 'COMPLETED': (tr('Completed'), 'ok', false),
  'CANCELLED_BY_CUSTOMER': (tr('Cancelled by client'), 'bad', false), 'CANCELLED_BY_SALON': (tr('Cancelled by salon'), 'bad', false), 'NO_SHOW': (tr('No-show'), 'bad', false),
  // Trade orders
  'PLACED': (tr('Placed'), 'info', false), 'UNDER_REVIEW': (tr('Credit review'), 'warn', false), 'APPROVED': (tr('Approved'), 'info', false), 'DISPATCHED': (tr('Dispatched'), 'info', false),
  'OUT_FOR_DELIVERY': (tr('Out for delivery'), 'warn', true),
  'DELIVERED': (tr('Delivered'), 'ok', false),
  'CANCELLED': (tr('Cancelled'), 'bad', false),
  'FAILED_DELIVERY': (tr('Delivery failed'), 'bad', false),
  'PROCESSING': (tr('Processing'), 'info', false), 'RETURNED': (tr('Returned'), 'bad', false),
  // Salons
  'PENDING_VERIFICATION': (tr('Pending verification'), 'warn', false),
  'CHANGES_REQUESTED': (tr('Changes requested'), 'bad', false),
  'ACTIVE': (tr('Active'), 'ok', false),
  'SUSPENDED': (tr('Suspended'), 'bad', false),
  // Visits, leave, training, complaints, cash
  'PLANNED': (tr('Planned'), 'mute', false), 'PENDING': (tr('Pending'), 'warn', false), 'SCHEDULED': (tr('Scheduled'), 'info', false),
  'OPEN': (tr('Open'), 'warn', false), 'RESOLVED': (tr('Resolved'), 'ok', false),
};

/// Customer-facing wording where it differs from the salon's.
Map<String, String> get customerStatusLabels => {'CANCELLED_BY_CUSTOMER': tr('Cancelled by you'), 'DECLINED': tr("Salon couldn't take it")};

/// Lowercase confirmation word used in salon toasts.
String statusLabel(String s) => statusLabels[s]?.$1 ?? s;
