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
  Future<Account> signUp({required Role role, required String name, required String email, required String phone, required String password, String city = ''});
  Future<void> signOut();
  Future<void> updateProfile({required String name, required String phone, required String city});
  Future<void> changePassword(String current, String next);
  /// Resets a forgotten password, proving identity with the account's phone number.
  Future<void> resetPassword({required String email, required String phone, required String newPassword});
  Future<void> deleteAccount(String password);
}

/// Device preferences that survive restarts.
abstract interface class PreferencesRepository {
  String get theme; // system | light | dark
  set theme(String v);
  bool get sound;
  set sound(bool v);
  String get language; // en | ur
  set language(String v);
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
  Salon? salonOfOwner(String accountId);
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
  Future<void> deleteBranch(String branchId);
  Future<void> updatePolicy(String salonId, {required bool autoConfirm, required int cancelWindowHours, required int noShowGraceMin});

  // Menu
  Future<ServiceItem> saveService({String? id, required String salonId, required String name, required String category, required String description, required int price, required int durationMin, bool active = true});
  Future<void> setServiceActive(String id, bool active);
  Future<void> deleteService(String id);

  // Team
  Future<Account> addStaff(String salonId, {required String name, required String email, required String phone, required String password, required String title});
  Future<void> updateStaff(String accountId, {required String title, required bool bookable, required List<Shift?> week});
  Future<void> removeStaff(String accountId);
  Future<LeaveRequest> requestLeave({required DateTime from, required DateTime to, required String reason});
  Future<void> decideLeave(String leaveId, {required bool approve});
  Future<void> cancelLeave(String leaveId);

  // Customers
  Future<bool> toggleFavourite(String salonId);

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
  List<Appointment> forStaff(String staffId);
  /// Customers the salon has served (for its client list).
  bool canCancelFree(Appointment a);
  bool canMarkNoShow(Appointment a);

  Future<Appointment> book({required String salonId, required String branchId, required List<String> serviceIds, String? staffId, required DateTime start, String notes = ''});
  Future<Appointment> walkIn({required String salonId, required String branchId, required String guestName, required String guestPhone, required List<String> serviceIds, required String staffId, required DateTime start});
  Future<void> confirm(String id);
  Future<void> decline(String id, String reason);
  Future<void> cancel(String id, String reason);
  Future<void> reschedule(String id, DateTime start, {String? staffId});
  Future<void> checkIn(String id);
  Future<void> startService(String id);
  Future<void> complete(String id);
  Future<void> noShow(String id);
}

// ─── Reviews, complaints, chat, notifications ────────────────────────────────

abstract interface class EngagementRepository implements Observable {
  List<Review> reviewsForSalon(String salonId);
  Review? reviewForAppointment(String appointmentId);
  Future<Review> addReview({required String appointmentId, required int stars, required String text});
  Future<void> replyToReview(String reviewId, String reply);

  List<Complaint> complaintsForSalon(String salonId);
  List<Complaint> complaintsForCustomer(String customerId);
  Future<Complaint> raiseComplaint({required String salonId, String? appointmentId, required String topic, required String text});
  Future<void> resolveComplaint(String id, String response);

  List<ChatThread> threadsForCustomer(String customerId);
  List<ChatThread> threadsForSalon(String salonId);
  ChatThread? thread(String id);
  Future<ChatThread> openThread(String salonId);
  List<ChatMessage> messages(String threadId);
  ChatMessage? lastMessage(String threadId);
  /// Unread messages in [threadId] for the side viewing it.
  int unread(String threadId, {required bool asSalon});
  Future<void> send(String threadId, String text, {required bool asSalon});
  Future<void> markThreadRead(String threadId, {required bool asSalon});

  List<AppNotification> notifications();
  int unreadNotifications();
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead();
}

// ─── Trade: catalogue, orders, credit, delivery ──────────────────────────────

class CreditSummary {
  final int limit, outstanding, overdue, days;
  final DateTime? lastPaymentAt;
  final int lastPayment;
  const CreditSummary({required this.limit, required this.outstanding, required this.overdue, required this.days, this.lastPaymentAt, this.lastPayment = 0});
  int get available => limit - outstanding;
}

class CartLine {
  final String productId, variantId;
  final int qty;
  const CartLine(this.productId, this.variantId, this.qty);
}

abstract interface class TradeRepository implements Observable {
  List<Product> products({bool activeOnly = true});
  Product? product(String id);
  Future<Product> saveProduct({String? id, required String name, required String category, required String description, required int color, required String shape, required List<Variant> variants, required int schemeBuy, required int schemeFree, bool active = true});
  Future<void> restock(String productId, String variantId, int qty);

  /// Lines priced with schemes applied (what the order would be).
  List<OrderLine> quote(List<CartLine> cart);
  Future<TradeOrder> placeOrder({required String salonId, required List<CartLine> cart, required PaymentMethod payment, String notes = ''});
  TradeOrder? order(String id);
  List<TradeOrder> ordersForSalon(String salonId);
  List<TradeOrder> allOrders();
  List<TradeOrder> ordersForRider(String riderId);

  Future<void> approveOrder(String id);
  Future<void> cancelOrder(String id, String reason);
  Future<void> dispatch(String id, String riderId);
  Future<void> startDelivery(String id);
  Future<void> deliver(String id, {required String recipientName, required Strokes signature, int? cashCollected});
  Future<void> failDelivery(String id, String reason);
  Future<void> confirmReceipt(String id);

  CreditSummary credit(String salonId);
  List<CreditEntry> statement(String salonId);
  Future<void> setCreditTerms(String salonId, {required int limit, required int days});
  Future<void> recordPayment(String salonId, int amount, String note);

  /// COD cash a rider holds (delivered, not yet handed over).
  List<TradeOrder> cashOnHand(String riderId);
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
  Future<void> checkIn(String visitId);
  Future<void> completeVisit(String visitId, {required List<String> outcomes, required String notes, DateTime? followUpAt});
  Future<void> cancelVisit(String visitId);

  List<Training> trainings();
  Training? training(String id);
  Future<Training> saveTraining({String? id, required String title, required String description, required String location, required DateTime at, required int durationMin, required int seats});
  Future<void> cancelTraining(String id);
  Future<void> enrol(String trainingId);
  Future<void> withdraw(String trainingId);
  Future<void> completeTraining(String id, List<String> attendedIds);

  List<DailyReport> reports(String officerId);
  DailyReport? reportFor(String officerId, DateTime day);
  Future<DailyReport> submitReport({required String notes});
}
