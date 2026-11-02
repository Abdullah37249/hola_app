/// Terms of use and privacy policy shown in the app.
///
/// DRAFT written from what the app does today. HOLA must review and approve
/// the wording before release; then set [legalReviewed] to true, which
/// removes the "draft" notice from both pages.
const legalReviewed = false;

/// Date shown as "Last updated".
const legalUpdated = '31 October 2026';

typedef LegalSection = (String heading, String body);

const termsOfUse = <LegalSection>[
  (
    'About HOLA',
    'HOLA Professional connects clients with salons, and connects salons with the HOLA team for products, training and support. '
        'By creating an account or using the app, you agree to these terms.',
  ),
  (
    'Your account',
    'Give your real name and contact details, and keep your password private. You are responsible for what happens under your account. '
        'Customers create their own accounts. Salon staff are added by their salon owner. HOLA team accounts are set up by HOLA.',
  ),
  (
    'Booking appointments',
    'A booking is a request until the salon confirms it, unless the salon confirms bookings automatically. '
        'Prices and times come from the salon. Each salon sets how late you can cancel for free and when a missed appointment counts as a no-show. '
        'If you can\'t make it, cancel in the app as early as you can.',
  ),
  (
    'Paying',
    'You pay the salon directly, at the salon. HOLA does not take payments from clients in the app. '
        'Product orders from salons are paid in cash on delivery or on HOLA credit, as agreed with HOLA.',
  ),
  (
    'Salons on HOLA',
    'Salon owners must keep their salon\'s details, services, prices and opening hours accurate, and only upload photos they have the right to use. '
        'HOLA may verify a salon, ask for changes, or suspend a salon that breaks these terms.',
  ),
  (
    'Reviews, messages and complaints',
    'Keep reviews honest and about your own visit. Don\'t post anything abusive, false or private about someone else. '
        'HOLA may hide or remove content that breaks these rules.',
  ),
  ('Using the app fairly', 'Don\'t misuse the app, try to access other people\'s accounts, make fake bookings or reviews, or interfere with how it works.'),
  (
    'Closing your account',
    'You can delete your account at any time from your profile. HOLA may suspend accounts that break these terms. '
        'A salon owner can\'t delete their account while their salon is on HOLA.',
  ),
  ('Changes to these terms', 'We may update these terms as HOLA grows. We will show the new date at the top, and tell you in the app about important changes.'),
  ('Contact', 'Questions about these terms? Send them through Feedback & complaints in the app, or ask your HOLA sales officer.'),
];

const privacyPolicy = <LegalSection>[
  ('What this covers', 'This explains what information HOLA Professional keeps about you, why, and the choices you have.'),
  (
    'What we keep',
    'Your account: name, email, phone number, city and your role. Your password is never stored as typed; only a scrambled (salted hash) version is kept.\n'
        'Salons: salon name, phone, description, branches and addresses, opening hours, services and prices, team members and their working hours, and photos.\n'
        'Bookings: the salon, services, times, staff member, status and any note you add.\n'
        'Reviews, complaints and messages you send in the app.\n'
        'For HOLA product orders and deliveries: order details, the name of the person who received the delivery, their signature and the cash collected.\n'
        'For the HOLA team: salon visits, visit notes, training sessions and daily reports.\n'
        'Your settings, such as appearance and sounds.',
  ),
  (
    'Why we use it',
    'To run your account and sign you in, to let clients book salons and salons manage those bookings, to send you notifications about your bookings and orders, '
        'to deliver HOLA products, and to keep HOLA safe and fair, for example to stop fake bookings or reviews.',
  ),
  (
    'Who can see it',
    'The salon you book with sees your name, phone number and your booking. Salon staff see the bookings they are working on. '
        'The HOLA team sees salon details needed to verify salons, take orders and deliver products. Delivery riders see the delivery address and order. '
        'Reviews you post can be seen by other clients once they are approved.',
  ),
  (
    'Where it is stored',
    'At the moment, HOLA keeps your information only on this phone, in storage that other apps can\'t read. Uninstalling the app removes it. '
        'When HOLA moves to its online service, your information will be stored securely on HOLA\'s servers so it works on any phone, and this policy will be updated first.',
  ),
  ('What we don\'t do', 'We don\'t sell your information, and we don\'t show ads. If your phone offers to save your password, that is handled by your phone or Google, not by HOLA.'),
  ('Your choices', 'You can update your name, phone and city in your profile, change your password, and delete your account at any time. Deleting your account removes your profile from HOLA.'),
  ('Children', 'HOLA is meant for adults. If you are under 18, use it only with a parent or guardian\'s permission.'),
  ('Changes to this policy', 'We will show the new date at the top when this policy changes, and tell you in the app about important changes.'),
  ('Contact', 'Questions about your information? Send them through Feedback & complaints in the app, or ask your HOLA sales officer.'),
];
