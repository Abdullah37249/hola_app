import 'dart:io';
// Repository contracts. Views and viewmodels depend on these only; the data
// layer implements them (on-device today, the HOLA API later).
//
// Every repository exposes [changes]: it fires after any write anywhere, so a
// viewmodel listening to it stays in sync across roles (a booking a customer
// makes shows up on the salon's screens straight away).

import 'package:flutter/foundation.dart';

import '../entities/entities.dart';
import '../services/availability.dart';

/// A rule was broken (wrong password, slot taken…). [message] is user-facing.
/// Most photos a salon can show.
const maxSalonPhotos = 8;

/// What a salon gives when it signs up: its name and main address.
class SalonDraft {
  final String name, address, area;

  /// GPS captured at the salon's door during sign-up, if the owner did.
  final GeoFix? location;
  const SalonDraft({required this.name, this.address = '', this.area = '', this.location});
}

class DomainError implements Exception {
  final String message;

  /// The form field the error is about ('email', 'password', 'name', ...), if any,
  /// so forms can show it under that field.
  final String? field;
  const DomainError(this.message, {this.field});
  @override
  String toString() => message;
}

abstract interface class Observable {
  Listenable get changes;
}

// ─── Accounts ────────────────────────────────────────────────────────────────

abstract interface class AuthRepository implements Observable {
  /// Loads the database and the saved session. Call once at start-up.
  Future<void> init();
  Account? get current;
  Account? account(String id);
  List<Account> accountsWithRole(Role role);

  Future<Account> signIn(String email, String password);

  /// [salon] is required for a salon account: the salon is created with it.
  Future<Account> signUp({required Role role, required String name, required String email, required String phone, required String password, String city = '', SalonDraft? salon});
  Future<void> signOut();

  // ── fingerprint sign-in (each account on its own) ──

  bool fingerprintOn(String accountId);

  /// Signed out: the accounts a fingerprint can sign back in.
  List<FingerprintAccount> get resumable;

  /// Signs [accountId] back in with its kept session (after a fingerprint match).
  Future<Account> resumeWithFingerprint(String accountId);

  /// For the signed-in account (call after a fingerprint match).
  Future<void> enableFingerprint();

  /// For [accountId], or the signed-in account.
  Future<void> disableFingerprint([String? accountId]);

  /// Asked once per account after its first password sign-in.
  bool fingerprintOffered(String accountId);
  Future<void> markFingerprintOffered(String accountId);
  Future<void> updateProfile({required String name, required String phone, required String city});
  Future<void> changePassword(String current, String next);

  /// Resets a forgotten password, proving identity with the account's phone number.
  /// Accounts live on the HOLA server (passwords are reset by emailed link).
  bool get usesServer;

  /// Asks HOLA to email a password reset link (server accounts).
  Future<void> requestPasswordReset(String email);
  Future<void> resetPassword({required String email, required String phone, required String newPassword});
  Future<void> deleteAccount(String password);
}

/// Device preferences that survive restarts.
abstract interface class PreferencesRepository {
  /// Loads stored settings; call once at start-up.
  Future<void> init();
  String get theme; // system | light | dark
  set theme(String v);
  bool get sound;
  set sound(bool v);
  String get language; // en | ur
  set language(String v);

  /// The one-time permissions screen has been shown.
  bool get permissionsAsked;
  set permissionsAsked(bool v);
}

// ─── Salons ──────────────────────────────────────────────────────────────────

class SalonRating {
  final double average;
  final int count;
  const SalonRating(this.average, this.count);
}

abstract interface class SalonRepository implements Observable {
  // Reads
  List<Salon> allSalons();

  /// Active salons customers can book, optionally filtered.
  List<Salon> discover({String query = '', String? category, String? city});
  Salon? salon(String id);
  List<Branch> branches(String salonId);
  Branch? branch(String id);
  List<ServiceItem> services(String salonId, {bool activeOnly = false});
  ServiceItem? service(String id);
  List<String> categoriesOf(String salonId);
  int fromPrice(String salonId);
  SalonRating rating(String salonId);
  List<StaffProfile> staff(String salonId);
  StaffProfile? staffProfile(String accountId);
  List<LeaveRequest> leave(String salonId);
  List<LeaveRequest> leaveFor(String staffId);
  bool isFavourite(String salonId);

  // Setup (salon owner)
  Future<Salon> createSalon({required String name, required String phone, required String about, required String branchName, required String address, required String area, required String city});
  Future<void> updateSalon(String salonId, {required String name, required String phone, required String about});

  /// Replaces the salon's photo list (file names); the first is the cover. Owner only, at most [maxSalonPhotos].
  Future<void> setSalonPhotos(String salonId, List<String> photos);
  Future<Branch> addBranch(String salonId, {required String name, required String address, required String area, required String city});
  Future<void> updateBranch(String branchId, {required String name, required String address, required String area, required String city, required List<Shift?> hours});

  /// Saves where the branch is (GPS), so riders can navigate to it.
  Future<void> setBranchLocation(String branchId, GeoFix at);
  Future<void> deleteBranch(String branchId);
  Future<void> updatePolicy(String salonId, {required bool autoConfirm, required int cancelWindowHours, required int noShowGraceMin});

  // Menu
  Future<ServiceItem> saveService({
    String? id,
    required String salonId,
    required String name,
    required String category,
    required String description,
    required int price,
    required int durationMin,
    bool active = true,
  });
  Future<void> setServiceActive(String id, bool active);
  Future<void> deleteService(String id);

  // Offers & discounts
  /// Every offer of a salon (the salon's list), newest first.
  List<ServiceOffer> offers(String salonId);

  /// Offers customers can see now: running, on a listed salon's visible
  /// service, and not already used by the signed-in customer. [salonId]
  /// narrows it to one salon.
  List<ServiceOffer> liveOffers({String? salonId});

  /// The signed-in customer's use of [offer]: [OfferUse.none], reserved or used.
  String offerUse(ServiceOffer offer);

  /// The booking holding [offer] for the signed-in customer (its code), if any.
  String heldOn(ServiceOffer offer);

  /// Salon side: how many clients spent [offer] (completed) and hold it (open bookings).
  ({int used, int held}) offerStats(ServiceOffer offer);

  /// The best running offer on [serviceId] the signed-in customer can still use.
  ServiceOffer? offerFor(String serviceId);

  /// Creates or edits an offer. [startDay] and [lastDay] are whole days.
  Future<ServiceOffer> saveOffer({
    String? id,
    required String salonId,
    required String serviceId,
    required String discountType,
    required int discountValue,
    required DateTime startDay,
    required DateTime lastDay,
    required bool active,
  });
  Future<void> setOfferActive(String id, bool active);
  Future<void> deleteOffer(String id);

  /// Offers from HOLA: a salon's own list ([salonId]), or the customer's view.
  Future<void> syncOffers({String? salonId});

  // Team
  /// Team members don't sign in: the salon account manages their hours,
  /// bookings, time off and training.
  Future<Account> addStaff(String salonId, {required String name, String phone = '', required String title});

  /// [branchId]: where they work (their shifts are at that branch).
  Future<void> updateStaff(String accountId, {required String title, required bool bookable, required List<Shift?> week, String? branchId});
  Future<void> removeStaff(String accountId);

  /// The salon adds time off for a team member ([staffId]); it is approved at once.
  Future<LeaveRequest> requestLeave({required String staffId, required DateTime from, required DateTime to, required String reason});
  Future<void> decideLeave(String leaveId, {required bool approve});
  Future<void> cancelLeave(String leaveId);

  // Customers
  Future<bool> toggleFavourite(String salonId);

  /// Brings in the salons HOLA has made live (GET /discover/salons) with their
  /// branches, hours and menus. Does nothing when the app isn't connected.
  Future<void> syncDirectory();

  /// The signed-in salon's own listing and booking policy, from HOLA.
  Future<void> syncMySalon(String salonId);

  // HOLA verification (sales officer)
  Future<void> approveSalon(String salonId);
  Future<void> requestChanges(String salonId, String note);
  Future<void> suspendSalon(String salonId, String note);
  Future<void> reactivateSalon(String salonId);

  /// Owner re-submits after changes were requested.
  Future<void> resubmitSalon(String salonId);
}

// ─── Bookings ────────────────────────────────────────────────────────────────

abstract interface class BookingRepository implements Observable {
  List<Slot> availability({required String branchId, required List<String> serviceIds, String? staffId, required DateTime day, String? rescheduling});
  Appointment? appointment(String id);
  List<Appointment> forCustomer(String customerId);
  List<Appointment> forSalon(String salonId);

  /// HOLA's client list for a salon, as last loaded by [syncClients]
  /// (empty when offline or before the first load).
  List<ClientRecord> clientList(String salonId);

  /// Loads the salon's whole client list from HOLA.
  Future<void> syncClients(String salonId);

  /// A HOLA booking's full timeline (who changed what, when, and why).
  Future<void> syncBookingHistory(String id);

  /// Loads every booking of one client at the salon, with no date window:
  /// an app client by [customerId], a walk-in by [phone] (else [name]).
  Future<void> syncClientHistory(String salonId, {String? customerId, String phone = '', String name = ''});

  bool canCancelFree(Appointment a);
  bool canMarkNoShow(Appointment a);

  Future<Appointment> book({required String salonId, required String branchId, required List<String> serviceIds, String? staffId, required DateTime start, String notes = ''});
  Future<Appointment> walkIn({
    required String salonId,
    required String branchId,
    required String guestName,
    required String guestPhone,
    required List<String> serviceIds,
    required String staffId,
    required DateTime start,
  });
  Future<void> confirm(String id);
  Future<void> decline(String id, String reason);
  Future<void> cancel(String id, String reason);
  Future<void> reschedule(String id, DateTime start, {String? staffId});
  Future<void> checkIn(String id);
  Future<void> startService(String id);
  Future<void> complete(String id);
  Future<void> noShow(String id);

  /// HOLA salons: loads free times from the server for [days] days from
  /// [from]; [availability] then answers from what was loaded.
  Future<void> loadAvailability({required String branchId, required List<String> serviceIds, String? staffId, required DateTime from, int days = 14});

  /// Brings in the signed-in person's bookings from the HOLA server (a
  /// customer's own, or a HOLA salon's calendar). Does nothing offline-only.
  Future<void> sync();
}

// ─── Order returns: replacement, outstanding adjustment, voucher ─────────────

/// A salon returns products from a delivered order: for a replacement, or for
/// money back (taken off the outstanding balance for a credit order; settled
/// by a voucher or a replacement, as HOLA proposes, for a cash order). HOLA
/// decides every request; its team does that in the HOLA dashboard (or, on an
/// on-device setup, a sales officer in this app).
abstract interface class ReturnRepository implements Observable {
  /// HOLA's returns API is switched on (on-device setups always work).
  bool get live;

  /// A salon's requests, newest first; HOLA's team sees every salon's.
  List<ReturnRequest> returns({String? salonId});
  ReturnRequest? returnRequest(String id);
  List<ReturnRequest> returnsForOrder(String orderId);

  /// The order can be returned: delivered (or receipt confirmed) and with
  /// units not already in another request.
  bool canReturn(TradeOrder o);

  /// Units of [variantId] on [o] that no open or settled request holds yet.
  int returnable(TradeOrder o, String variantId);

  /// What one unit of [variantId] gives back: what was paid for the line
  /// (free units included, coupon taken off) per unit.
  int unitValue(TradeOrder o, String variantId);

  /// [qty]: variantId → units to return (at least one). [note] is required
  /// when [reason] is [ReturnReason.other]. [photoPaths]: up to 6 photos.
  Future<ReturnRequest> requestReturn({required String orderId, required String option, required String reason, String note = '', required Map<String, int> qty, List<String> photoPaths = const []});

  /// The salon withdraws a request HOLA hasn't decided yet.
  Future<void> cancelReturn(String id);

  /// The salon accepts HOLA's proposal (voucher or replacement) for a cash order.
  Future<void> acceptProposal(String id);
  Future<void> declineProposal(String id, String note);

  Future<void> syncReturns();
  Future<void> syncReturn(String id);

  // HOLA's side (the dashboard; on the device, a sales officer).
  Future<void> startReview(String id);

  /// Asks the salon something; the note goes into the return's conversation.
  Future<void> respond(String id, String note);
  Future<void> approveReturn(String id, {String note = ''});
  Future<void> rejectReturn(String id, String reason);

  /// For a cash order's money-back return: a voucher or a replacement (HOLA
  /// works out the amount from the order).
  Future<void> proposeSettlement(String id, {required String settlement, int validDays = 90, String note = ''});

  /// Sends a rider to collect the goods. Money moves only once they have.
  Future<void> assignPickup(String id, String riderId, {DateTime? expectedOn});

  // The rider.
  List<ReturnPickupTask> pickups();
  Future<void> syncPickups();

  /// The rider has the goods: HOLA settles the return (outstanding
  /// adjustment, voucher or replacement order).
  Future<void> collectPickup(String returnId);
}

// ─── Reviews, complaints, chat, notifications ────────────────────────────────

abstract interface class EngagementRepository implements Observable {
  /// Published reviews, newest first; [withPending] adds the ones still
  /// waiting for HOLA to publish them (for the salon's own eyes).
  List<Review> reviewsForSalon(String salonId, {bool withPending = false});
  Review? reviewForAppointment(String appointmentId);

  /// [photos]: (path on this phone, BEFORE | AFTER | OTHER), up to 6.
  Future<Review> addReview({required String appointmentId, required int stars, required String text, List<(String, String)> photos = const []});

  /// A HOLA salon's published reviews (with photos), for its page.
  Future<void> syncSalonReviews(String salonId);

  /// A review photo as a file on this phone (downloaded once), or null.
  Future<File?> reviewPhotoFile(ReviewPhoto photo);

  /// Booking reminders (24 h and 2 h before a visit) for the signed-in customer.
  bool get remindersOn;

  /// Turns them on or off: on this phone and, for HOLA, the REMINDERS push.
  Future<void> setReminders(bool on);
  Future<void> replyToReview(String reviewId, String reply);

  /// The salon can delete reviews on its profile (they and their photos
  /// leave the profile and the rating). [reviewDelete]: HOLA allows it.
  bool get reviewDelete;
  Future<void> deleteReview(String reviewId);

  /// Feedback & complaints exist ([complaintsOn]): HOLA switched them off
  /// in contract 0.30.0, so their screens and entry points hide.
  bool get complaintsOn;

  List<Complaint> complaintsForSalon(String salonId);
  List<Complaint> complaintsForCustomer(String customerId);
  Future<Complaint> raiseComplaint({required String salonId, String? appointmentId, required String topic, required String text});
  Future<void> resolveComplaint(String id, String response);

  /// Brings in reviews and complaints from the HOLA server for the signed-in
  /// customer or HOLA salon. Does nothing when the app isn't connected.
  Future<void> sync();

  List<AppNotification> notifications();
  int unreadNotifications();
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead();

  /// Keeps a push from HOLA in the signed-in user's notification list.
  /// [inboxId]: HOLA's inbox entry for the push, so the next inbox sync
  /// doesn't list it twice.
  void receivePush(String title, String body, {NotifLink? link, String? inboxId});
}

// ─── Chat ────────────────────────────────────────────────────────────────────

/// Conversations of the signed-in person: a customer with salons, a salon
/// with its clients and riders, a rider with salons. Each one can be about a
/// booking or an order. Kept on the phone (history works offline) and, when
/// HOLA's chat is live, on the server with pushes for new messages.
abstract interface class ChatRepository implements Observable {
  /// Chat goes through HOLA (every phone sees the same conversations).
  bool get live;

  /// The signed-in person's side: [ChatSide.customer], salon or rider.
  String get mySide;

  /// Mine, most recent activity first.
  List<ChatThread> threads();
  ChatThread? thread(String id);

  /// Finds or starts a conversation. A customer passes [salonId]; a salon
  /// passes [customerId] or [riderId]; a rider passes [salonId] and
  /// [orderId]. [appointmentId] / [orderId] link it to a booking or order.
  Future<ChatThread> open({required String salonId, String? customerId, String? riderId, String? appointmentId, String? orderId});

  /// The salon can chat with HOLA's team (contract 0.23.0).
  bool get holaChat;

  /// The salon's conversation with HOLA's team: the general one, or the one
  /// about a return ([returnId]). HOLA's team passes the [salonId] it writes to.
  Future<ChatThread> openHola({required String salonId, String? returnId});

  /// Oldest first.
  List<ChatMessage> messages(String threadId);
  ChatMessage? lastMessage(String threadId);

  /// Messages from the other side not read yet.
  int unread(String threadId);
  int get unreadTotal;

  /// Sends text and/or photos ([imagePaths] are picked files).
  /// [ref]: an order, return or voucher shared as a card (HOLA ↔ salon chats).
  Future<void> send(String threadId, {String text = '', List<String> imagePaths = const [], MsgRef? ref});

  /// Sends a failed message again.
  Future<void> retry(String messageId);
  Future<void> markRead(String threadId);

  /// Brings in the conversation list (new and changed ones).
  Future<void> sync();

  /// Brings in new messages of one conversation.
  Future<void> syncThread(String threadId);

  /// Loads older history; false when there is none.
  Future<bool> loadOlder(String threadId);

  /// The photo as a file on this phone, downloading it from HOLA if needed.
  Future<File?> imageFile(ChatImage image);
}

// ─── Trade: catalogue, orders, credit, delivery ──────────────────────────────

class CreditSummary {
  final int limit, outstanding, overdue, days;
  final DateTime? lastPaymentAt;
  final int lastPayment;

  /// HOLA's figure, which also holds back credit orders awaiting approval.
  final int? _available;
  const CreditSummary({required this.limit, required this.outstanding, required this.overdue, required this.days, this.lastPaymentAt, this.lastPayment = 0, int? available}) : _available = available;
  int get available => _available ?? (limit - outstanding < 0 ? 0 : limit - outstanding);
}

class CartLine {
  final String productId, variantId;
  final int qty;
  const CartLine(this.productId, this.variantId, this.qty);
}

abstract interface class TradeRepository implements Observable {
  /// Officers may approve, dispatch, record payments, set credit terms,
  /// confirm cash and edit products on the phone (on-device mode only).
  /// With HOLA connected these happen in the HOLA dashboard.
  bool get officerToolsOnPhone;

  /// Refreshes HOLA's trade catalogue from the server (no-op on-device only).
  Future<void> syncCatalogue();
  List<Product> products({bool activeOnly = true});
  Product? product(String id);
  Future<Product> saveProduct({
    String? id,
    required String name,
    required String category,
    required String description,
    required int color,
    required String shape,
    required List<Variant> variants,
    required int schemeBuy,
    required int schemeFree,
    bool active = true,
  });
  Future<void> restock(String productId, String variantId, int qty);

  /// Lines priced with schemes applied (what the order would be).
  List<OrderLine> quote(List<CartLine> cart);

  /// Refreshes one salon's trade orders from the server (no-op on-device only).
  Future<void> syncOrders(String salonId);

  /// Refreshes one salon's HOLA credit: limit, balance and statement.
  Future<void> syncCredit(String salonId);

  /// The salon's payments towards its credit balance, newest first.
  List<PaymentRequest> paymentRequests(String salonId);

  /// What the salon owes minus payments already waiting for HOLA.
  int payableNow(String salonId);
  Future<void> syncPaymentRequests(String salonId);

  /// Tells HOLA the salon is paying [amount] by [method]. Online payments need
  /// a receipt photo ([proofPath]); HOLA finance confirms before it counts.
  Future<void> requestPayment(String salonId, {required PayMethod method, required int amount, String reference = '', String? proofPath, String note = '', String? riderId});

  /// True once salons pick a rider (and riders confirm) on HOLA.
  bool get canPickRider;

  /// HOLA riders in the salon's city, for "Pay to a rider".
  Future<List<RiderOption>> ridersFor(String salonId);

  /// Rider: salons waiting for this rider to confirm their cash.
  List<CollectionRequest> collections();
  Future<void> syncCollections();

  /// Rider: got the cash ([amount] may be less) → the salon's payment is paid.
  Future<void> confirmCollection(String id, int amount);
  Future<void> declineCollection(String id, String reason);
  Future<void> cancelPaymentRequest(String salonId, String requestId);

  /// Coupons HOLA sent this salon (promotions), newest first.
  List<SalonCoupon> coupons(String salonId);
  Future<void> syncCoupons(String salonId);

  /// Rider: a credit payment to collect along with this delivery, if any.
  CreditCollection? creditCollectionFor(String orderId);

  /// Rider: records the credit cash taken from the salon (may be less than asked).
  Future<void> collectCredit(String requestId, int amount);

  /// Copies the signed-in rider's deliveries from HOLA (assigned and finished).
  Future<void> syncDeliveries();

  /// HOLA needs a photo of the handover for this delivery.
  bool needsDeliveryPhoto(String id);
  // ── HOLA product reviews (the salon rates what it received) ──

  /// HOLA's product reviews API is live (on-device setups always work).
  bool get productReviewsLive;

  /// The salon can still rate products on this delivered order.
  bool canRateProducts(TradeOrder o);

  /// The salon's ratings on one order (variantId → review).
  Map<String, ProductReview> productReviewsOn(String orderId);

  /// (average, count) of a product's published reviews.
  (double, int) productRating(String productId);

  /// [ratings]: variantId → (1–5 stars, comment). Published straight away.
  Future<void> rateProducts(String orderId, Map<String, (int, String)> ratings);

  /// Every product review (HOLA's team; the dashboard on the server).
  List<ProductReview> allProductReviews();
  Future<void> deleteProductReview(String id);
  Future<void> syncProductReviews(String salonId);

  Future<TradeOrder> placeOrder({required String salonId, required List<CartLine> cart, required PaymentMethod payment, String notes = '', String? couponCode});

  /// HOLA prices the cart with [couponCode]. Throws (field couponCode) when the
  /// coupon can't be used, with HOLA's reason.
  Future<OrderQuote> quoteWithCoupon({required String salonId, required List<CartLine> cart, required String couponCode});
  TradeOrder? order(String id);
  List<TradeOrder> ordersForSalon(String salonId);
  List<TradeOrder> allOrders();
  List<TradeOrder> ordersForRider(String riderId);

  Future<void> approveOrder(String id);
  Future<void> cancelOrder(String id, String reason);
  Future<void> dispatch(String id, String riderId);
  Future<void> startDelivery(String id);
  Future<void> deliver(String id, {required String recipientName, required Strokes signature, int? cashCollected, GeoFix? where, String? photoPath});
  Future<void> failDelivery(String id, String reason);
  Future<void> confirmReceipt(String id);

  CreditSummary credit(String salonId);
  List<CreditEntry> statement(String salonId);
  Future<void> setCreditTerms(String salonId, {required int limit, required int days});
  Future<void> recordPayment(String salonId, int amount, String note);

  /// COD cash a rider holds (delivered, not yet handed over).
  List<TradeOrder> cashOnHand(String riderId);

  /// Cash the rider holds, not yet handed over (from HOLA when signed in there).
  List<CashPayment> cashHeld(String riderId);

  /// Fetches the rider's cash in hand from HOLA.
  Future<void> syncCash();
  Future<CashHandover> handOverCash();
  List<CashHandover> handovers({String? riderId});
  Future<void> confirmHandover(String id);
}

// ─── Field: visits, training, reports ────────────────────────────────────────

abstract interface class FieldRepository implements Observable {
  List<Visit> visits({String? officerId, DateTime? day});
  List<Visit> visitsForSalon(String salonId);
  Visit? visit(String id);
  Future<Visit> planVisit({required String salonId, required DateTime at, required String purpose});
  Future<void> checkIn(String visitId, {GeoFix? where});
  Future<void> completeVisit(String visitId, {required List<String> outcomes, required String notes, DateTime? followUpAt});
  Future<void> cancelVisit(String visitId);

  List<Training> trainings();
  Training? training(String id);

  /// Copies training sessions (and this salon's enrolments) from HOLA.
  Future<void> syncTrainings();
  Future<Training> saveTraining({String? id, required String title, required String description, required String location, required DateTime at, required int durationMin, required int seats});
  Future<void> cancelTraining(String id);

  /// Salon enrols itself or one of its team members ([personId], default: the signed-in account).
  Future<void> enrol(String trainingId, {String? personId});
  Future<void> withdraw(String trainingId, {String? personId});
  Future<void> completeTraining(String id, List<String> attendedIds);

  List<DailyReport> reports(String officerId);
  DailyReport? reportFor(String officerId, DateTime day);
  Future<DailyReport> submitReport({required String notes});
}
