/// Terms of use and privacy policy shown in the app.
///
/// Generated from the same text as the public pages (privacy.html, terms.html,
/// delete-account.html) so the app and the website always match. HOLA must
/// approve the wording; then set [legalReviewed] to true, which removes the
/// "draft" notice from both pages.
const legalReviewed = false;

/// Date shown as "Last updated".
const legalUpdated = '6 November 2026';

typedef LegalSection = (String heading, String body);

/// Terms of use.
const termsOfUse = <LegalSection>[
  (
    'About HOLA Professional',
    'HOLA Professional ("HOLA", "the app") is operated by MetaXperts. It connects clients with salons, and connects salons with the HOLA team for professional products, training and support. By creating an account or using the app, you agree to these terms. If you don\'t agree, please don\'t use the app.',
  ),
  (
    'Who can use HOLA',
    'You must be at least 18 years old, or use HOLA with the permission of a parent or guardian. Salon accounts must be opened by the salon\'s owner or someone allowed to act for the salon.',
  ),
  (
    'Your account',
    'Give your real name and contact details, and keep your password private. You are responsible for what happens under your account. Tell us straight away if you think someone else has used it. Customers and salon owners create their own accounts. Salon staff are invited by their salon owner. HOLA team accounts (sales officers, riders and trainers) are set up by HOLA. After several wrong passwords in a row, sign-in is paused for a short time to protect your account.',
  ),
  (
    'Booking appointments',
    'A booking is a request until the salon confirms it, unless the salon confirms bookings automatically. Services, prices and times come from the salon, and the salon is responsible for the service it provides. Each salon sets how late you can cancel for free and when a missed appointment counts as a no-show. If you can\'t make it, cancel in the app as early as you can.',
  ),
  (
    'Paying',
    'Clients pay the salon directly, at the salon. HOLA does not take card payments in the app. Salon orders for HOLA products are paid in cash on delivery or on HOLA credit, as agreed with HOLA. Salons on credit must pay their statement by the agreed date. Vouchers and offers have the conditions shown with them and can\'t be exchanged for cash.',
  ),
  (
    'Orders, deliveries and returns',
    'Product prices, stock and delivery are confirmed by HOLA when an order is approved. The person receiving a delivery confirms it in the app. Returns and replacements follow the reasons and steps shown in the app and are subject to HOLA\'s approval.',
  ),
  (
    'Salons on HOLA',
    'Salon owners must keep their salon\'s details, services, prices and opening hours accurate, and only upload photos they have the right to use. HOLA may ask for changes to, or suspend, a salon that breaks these terms.',
  ),
  (
    'Reviews, messages and photos',
    'Keep reviews honest and about your own visit or purchase. Don\'t post or send anything abusive, false, illegal or private about someone else. You keep ownership of what you post, and allow HOLA to show it in the app for the purpose it was posted. HOLA may hide or remove content that breaks these rules.',
  ),
  ('Using the app fairly', 'Don\'t misuse the app, try to access other people\'s accounts or data, make fake bookings, orders or reviews, or interfere with how HOLA works.'),
  (
    'Closing your account',
    'Customers can delete their account at any time from their profile in the app. Other accounts can ask for deletion from their profile (Request account deletion) or by emailing info@metaxperts.net. HOLA may suspend or close accounts that break these terms.',
  ),
  (
    'Availability and liability',
    'We work to keep HOLA available and accurate, but the app is provided as it is and may sometimes be unavailable. To the extent the law allows, HOLA is not responsible for services provided by salons, or for indirect losses. Nothing in these terms limits rights you have under the law.',
  ),
  (
    'Changes to these terms',
    'We may update these terms as HOLA grows. We will show the new date at the top, and tell you in the app about important changes. Using the app after a change means you accept the updated terms.',
  ),
  ('Contact', 'Questions about these terms? Email info@metaxperts.net.'),
];

/// Privacy policy.
const privacyPolicy = <LegalSection>[
  (
    'Who we are',
    'HOLA Professional is operated by MetaXperts, which is responsible for your information. This policy explains what information the app collects, why, who it is shared with, and the choices you have. Contact: info@metaxperts.net.',
  ),
  (
    'What we collect',
    'Account: your name, email address, phone number, city and role. Your password is sent over an encrypted connection and stored only in hashed form, never as typed.\nSalons: salon name, phone, description, branches and addresses, map location, opening hours, services and prices, team members and their working hours, and photos you upload.\nBookings: the salon, services, times, staff member, status and any note you add.\nOrders, deliveries and returns: products ordered, amounts, credit and payment records, payment proof images you upload, return reasons and photos, the name and signature of the person who received a delivery, delivery photos and cash collected.\nReviews and messages: reviews, replies and in-app messages with HOLA, including photos you attach.\nLocation: HOLA sales officers and riders share their precise location at the moment they check in at a salon or complete a delivery. A salon owner can use their location to pin the salon on the map. Location is read only at that moment, while the app is open. HOLA never tracks location in the background. When a customer taps Near me, the location is used on the phone to sort salons by distance and is not sent to HOLA.\nDevice: a notification token, the type of phone system and the app version, so we can send you notifications.\nSettings: your language, appearance and sound choices, kept on your phone.',
  ),
  (
    'What stays on your phone',
    'Fingerprint and Face ID are checked by your phone\'s operating system. HOLA never receives or stores your fingerprint or face data; it only learns whether the check passed. Your sign-in session is kept in your phone\'s secure storage.',
  ),
  (
    'Why we use it',
    'To create and run your account and sign you in; to let clients book salons and salons manage bookings; to take, deliver and account for HOLA product orders, credit and returns; to run training; to send notifications about your bookings, orders and messages; to provide support; and to keep HOLA safe, for example to stop fake bookings, fake reviews and repeated wrong-password attempts. We use your information only for running HOLA.',
  ),
  (
    'Who can see it',
    'The salon you book with sees your name, phone number and your booking. Salon staff see the bookings they work on. The HOLA team sees the salon and order details needed to take orders, deliver products and give support. Riders see the delivery address, contact and order. Approved reviews can be seen by other users of the app.',
  ),
  (
    'Service providers',
    'We use trusted providers to run HOLA: our hosting provider stores data on our servers; Google Firebase Cloud Messaging delivers notifications; maps in the app are loaded from OpenStreetMap, which receives your phone\'s internet address when map images load; and directions open in Google Maps or your maps app, under that provider\'s own privacy policy. We don\'t sell your information, share it for advertising, or show ads.',
  ),
  (
    'Security',
    'Information is sent between the app and our servers over encrypted (HTTPS) connections and stored on secured servers with access limited to people who need it. No system is perfectly secure, so please keep your password private.',
  ),
  (
    'How long we keep it',
    'We keep your information while your account is open. When an account is deleted, its profile and personal details are removed. Records we must keep by law, such as orders, invoices, payments and credit statements, are kept for as long as the law requires, and bookings and reviews may keep the name the salon saw.',
  ),
  (
    'Your choices and rights',
    'You can update your name, phone and city in your profile, change your password, turn notifications and location on or off in your phone\'s settings, and delete your account (customers in the app; other accounts on request). You can ask us for a copy of your information, or to correct or delete it, by emailing info@metaxperts.net. We will reply within 30 days.',
  ),
  (
    'Children',
    'HOLA is meant for adults and is not directed at children under 13. If you are under 18, use it only with a parent or guardian\'s permission. If you believe a child has given us information, contact us and we will delete it.',
  ),
  ('Changes to this policy', 'We will show the new date at the top when this policy changes, and tell you in the app about important changes.'),
  ('Contact', 'Questions or requests about your information? Email info@metaxperts.net.'),
];
