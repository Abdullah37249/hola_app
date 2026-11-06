import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hola_professional/core/network/api.dart';
import 'package:hola_professional/data/local/fingerprint_store.dart';
import 'package:hola_professional/data/local/local_auth_repository.dart';
import 'package:hola_professional/data/local/local_database.dart';
import 'package:hola_professional/data/local/local_salon_repository.dart';
import 'package:hola_professional/data/local/local_booking_repository.dart';
import 'package:hola_professional/data/local/local_engagement_repository.dart';
import 'package:hola_professional/data/local/storage.dart';
import 'package:hola_professional/domain/entities/entities.dart';
import 'package:hola_professional/domain/repositories/repositories.dart';

/// A tiny stand-in for the HOLA server, answering with the shapes the
/// backend team captured from staging (contract 0.7.1).
class FakeHola {
  final calls = <String>[];
  final users = <String, (String pw, Map<String, dynamic> me)>{};
  int refreshes = 0;
  bool accessExpired = false;
  bool slotTaken = false;
  bool ownerBookable = false;
  int memberVersion = 4;
  final team = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> ownerShifts = [];
  (String?, int)? uploaded;
  final appts = <String, Map<String, dynamic>>{};
  final idempotencyKeys = <String>[];
  final queries = <String, Map<String, String>>{};
  final bodies = <String, Map<String, dynamic>>{};

  int _seq = 0;
  Map<String, dynamic> tokens({bool expired = false}) => {
    'accessToken': 'a${++_seq}',
    'accessTokenExpiresAt': (expired ? DateTime.now().subtract(const Duration(minutes: 1)) : DateTime.now().add(const Duration(minutes: 15))).toIso8601String(),
    'refreshToken': 'r$_seq',
    'refreshTokenExpiresAt': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    'tokenType': 'Bearer',
  };

  String? signedIn;

  /// Whose session each refresh token is, and which HOLA has ended.
  final refreshOwner = <String, String>{};
  final revoked = <String>{};

  http.Response json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
  http.Response problem(int status, String code, [List<Map<String, String>> errors = const []]) =>
      json({'type': 'urn:hola:problem', 'title': 'x', 'status': status, 'code': code, 'detail': code, if (errors.isNotEmpty) 'errors': errors}, status);

  Map? registeredSalon;

  final salonJson = {
    'id': 'salon-1',
    'name': 'Shape Salon',
    'description': 'Colour studio',
    'city': 'Lahore',
    'branches': [
      {
        'id': 'br-1',
        'name': 'Main branch',
        'addressLine': '12 Main Blvd',
        'area': 'Gulberg',
        'city': 'Lahore',
        'phone': '+92 300 1234567',
        'hours': [
          {'weekday': 0, 'closed': false, 'opens': '12:00', 'closes': '18:00'},
          {'weekday': 1, 'closed': false, 'opens': '10:00', 'closes': '20:00'},
        ],
      },
    ],
  };

  Map<String, dynamic> appt(String id, String startsAt, String status) {
    final start = DateTime.parse(startsAt);
    return {
      'id': id,
      'code': 'HB-000001',
      'salon': {'id': 'salon-1', 'name': 'Shape Salon'},
      'branch': {'id': 'br-1', 'name': 'Main branch', 'addressLine': '12 Main Blvd', 'city': 'Lahore'},
      'customer': {'id': 'c1', 'fullName': 'Mariam', 'phone': '+923000000002'},
      'staff': {'id': 'mem-1', 'fullName': 'Noor Fatima'},
      'startsAt': start.toUtc().toIso8601String(),
      'endsAt': start.add(const Duration(minutes: 90)).toUtc().toIso8601String(),
      'status': status,
      'items': [
        {'branchServiceId': 'svc-1', 'name': 'Root colour', 'price': '2500.00', 'durationMin': 90},
      ],
      'totalPrice': '2500.00',
      'notes': null,
      'lateCancel': false,
      'freeCancelUntil': start.subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
      'allowedActions': ['cancel', 'reschedule'],
      'version': 1,
      'createdAt': '2026-11-02T06:00:00Z',
    };
  }

  late final client = MockClient((req) async {
    final path = req.url.path.replaceFirst('/api/v1', '');
    calls.add('${req.method} $path');
    queries[path] = req.url.queryParameters;
    // Only JSON bodies are read as text; photo bytes stay binary.
    final isJson = (req.headers['content-type'] ?? '').startsWith('application/json');
    final body = !isJson || req.bodyBytes.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    bodies['${req.method} $path'] = body;
    switch ('${req.method} $path') {
      case 'POST /auth/login':
        final u = users[body['email']];
        if (u == null || u.$1 != body['password']) return problem(401, 'INVALID_CREDENTIALS');
        signedIn = body['email'];
        final t = tokens(expired: accessExpired);
        refreshOwner[t['refreshToken'] as String] = body['email'] as String;
        return json(t);
      case 'POST /auth/register':
        if (users.containsKey(body['email'])) return problem(409, 'EMAIL_TAKEN');
        if ((body['password'] as String).length < 8) {
          return problem(422, 'VALIDATION_FAILED', [
            {'path': 'password', 'message': 'Too small'},
          ]);
        }
        users[body['email']] = (
          body['password'],
          {'id': 'cust-${users.length}', 'kind': 'CUSTOMER', 'email': body['email'], 'fullName': body['fullName'], 'phone': body['phone'], 'roles': [], 'createdAt': '2026-11-02T06:00:00Z'},
        );
        signedIn = body['email'];
        return json(tokens(), 201);
      case 'POST /auth/register-salon':
        final salon = body['salon'] as Map;
        users[body['email']] = (
          body['password'],
          {
            'id': 'owner-new',
            'kind': 'SALON',
            'email': body['email'],
            'fullName': body['fullName'],
            'roles': [
              {'role': 'SALON_OWNER', 'scopeId': 'salon-1', 'branchIds': []},
            ],
            'createdAt': '2026-11-02T06:00:00Z',
          },
        );
        registeredSalon = salon;
        signedIn = body['email'];
        return json(tokens(), 201);
      case 'GET /discover/salons/salon-1':
        return json(salonJson);
      case 'GET /branches/br-1/availability':
        return json({
          'branchId': 'br-1',
          'durationMin': 90,
          'totalPrice': '2500.00',
          'staff': [
            {'id': 'mem-1', 'fullName': 'Noor Fatima', 'title': 'Senior Stylist'},
          ],
          'days': [
            {
              'date': '2026-11-03',
              'closed': false,
              'fullyBooked': false,
              'slots': [
                {
                  'start': '2026-11-03T05:00:00.000Z',
                  'end': '2026-11-03T06:30:00.000Z',
                  'staffIds': ['mem-1'],
                },
              ],
            },
          ],
        });
      case 'POST /appointments':
        idempotencyKeys.add(req.headers['Idempotency-Key'] ?? req.headers['idempotency-key'] ?? '');
        if (slotTaken) return problem(409, 'APPOINTMENT_SLOT_TAKEN');
        final a = appt('ap-1', body['startsAt'] as String, 'REQUESTED');
        appts['ap-1'] = a;
        return json(a, 201);
      case 'GET /me/appointments':
        return json({
          'data': appts.values.toList(),
          'meta': {'page': 1, 'pageSize': 100, 'total': appts.length, 'totalPages': 1},
        });
      case 'POST /appointments/ap-1/cancel':
        appts['ap-1'] = {...appts['ap-1']!, 'status': 'CANCELLED_BY_CUSTOMER', 'allowedActions': []};
        return json(appts['ap-1']);
      case 'GET /salons/salon-1/appointments':
        final page = int.parse(req.url.queryParameters['page'] ?? '1');
        return json({
          'data': [appt('ap-$page', '2026-11-0${page + 2}T06:00:00Z', 'REQUESTED')],
          'meta': {'page': page, 'pageSize': 100, 'total': 2, 'totalPages': 2},
        });
      case 'POST /appointments/ap-1/confirm':
        return json({...appt('ap-1', '2026-11-03T06:00:00Z', 'CONFIRMED')});
      case 'PATCH /me':
        if (body['version'] != 3) return problem(409, 'VERSION_CONFLICT');
        users[signedIn]!.$2['fullName'] = body['fullName'];
        users[signedIn]!.$2['phone'] = body['phone'];
        return json(users[signedIn]!.$2);
      case 'POST /me/password':
        if (body['currentPassword'] != users[signedIn]!.$1) return problem(401, 'INVALID_CREDENTIALS');
        return http.Response('', 204);
      case 'POST /auth/password/forgot':
        return http.Response('', 202);
      case 'POST /me/delete-account':
        if (body['password'] != users[signedIn]!.$1) return problem(401, 'INVALID_CREDENTIALS');
        return http.Response('', 204);
      case 'POST /reviews':
        return json({'id': 'rev-1', 'rating': body['rating'], 'status': 'PENDING'}, 201);
      case 'GET /salons/salon-1/staff':
        return json([
          {'id': 'mem-1', 'userId': 'owner-1', 'fullName': 'Noor Fatima', 'title': 'Owner', 'bookable': ownerBookable, 'active': true, 'version': memberVersion},
          ...team,
        ]);
      case 'POST /salons/salon-1/staff':
        if (body.containsKey('email')) return problem(422, 'VALIDATION_FAILED');
        final m = {
          'id': 'mem-${team.length + 2}',
          'userId': 'u-x',
          'fullName': body['fullName'],
          'email': null,
          'loginEnabled': false,
          'title': body['title'],
          'bookable': true,
          'active': true,
          'version': 1,
        };
        team.add(m);
        return json(m, 201);
      case 'PUT /salons/salon-1/staff/mem-2/schedule':
        return json(body);
      case 'GET /salons/salon-1/staff/mem-2/schedule':
        return json({'shifts': bodies['PUT /salons/salon-1/staff/mem-2/schedule']?['shifts'] ?? []});
      case 'PATCH /salons/salon-1/staff/mem-1':
        if (body['version'] != memberVersion) return problem(409, 'VERSION_CONFLICT');
        ownerBookable = body['bookable'] == true;
        memberVersion++;
        return json({'id': 'mem-1', 'bookable': ownerBookable, 'version': memberVersion});
      case 'PUT /salons/salon-1/staff/mem-1/schedule':
        ownerShifts = (body['shifts'] as List).cast<Map<String, dynamic>>();
        return json(body);
      case 'GET /salons/salon-1/staff/mem-1/schedule':
        return json({'shifts': ownerShifts});
      case 'PUT /salons/salon-1/branches/br-1/hours':
        return json(body);
      case 'GET /services':
        return json([
          {'id': 'cat-1', 'name': 'Root Colour', 'defaultDurationMin': 60},
        ]);
      case 'POST /salons/salon-1/branches/br-1/services':
        if ((body['serviceId'] == null) == (body['name'] == null)) {
          return problem(422, 'VALIDATION_FAILED', [
            {'path': 'name', 'message': 'one of'},
          ]);
        }
        return json({'id': 'svc-2'}, 201);
      case 'GET /salons/salon-1':
        return json({'id': 'salon-1', 'version': 7});
      case 'PATCH /salons/salon-1':
        if (body['version'] != 7) return problem(409, 'VERSION_CONFLICT');
        return json({'id': 'salon-1', 'version': 8});
      case 'GET /salons/salon-1/branches':
        return json([
          {'id': 'br-1', 'version': 2},
        ]);
      case 'PATCH /salons/salon-1/branches/br-1':
        if (body['version'] != 2) return problem(409, 'VERSION_CONFLICT');
        return json({'id': 'br-1', 'version': 3});
      case 'PUT /files/file-1/content':
        uploaded = (req.headers['content-type'], req.bodyBytes.length);
        return json({'id': 'file-1', 'status': 'READY'});
      case 'POST /files':
        return json({'id': 'file-1', 'status': 'PENDING'}, 201);
      case 'PUT /salons/salon-1/photos':
        return json([
          for (final (i, id) in (body['fileIds'] as List).indexed) {'id': id, 'url': 'https://test/api/v1/public/files/$id', 'position': i},
        ]);
      case 'POST /complaints':
        return json({'id': 'cmp-1', 'code': 'HT-000001', 'status': 'OPEN'}, 201);
      case 'GET /complaints':
        return json({
          'data': [
            {
              'id': 'cmp-1',
              'subject': 'Waiting time',
              'status': 'OPEN',
              'raisedBy': {'id': 'c1', 'fullName': 'Mariam'},
              'salon': {'id': 'salon-1', 'name': 'Shape Salon'},
              'createdAt': '2026-11-02T06:00:00Z',
            },
          ],
          'meta': {'page': 1, 'totalPages': 1},
        });
      case 'GET /complaints/cmp-1':
        return json({
          'id': 'cmp-1',
          'description': 'Waited 30 minutes past my time.',
          'appointmentId': null,
          'resolution': null,
          'messages': [
            {
              'id': 'm1',
              'author': {'id': 'owner-1', 'fullName': 'Noor', 'staff': false},
              'body': 'Sorry, we added a stylist.',
              'internal': false,
            },
          ],
        });
      case 'POST /complaints/cmp-1/messages':
        return json({'id': 'm2'}, 201);
      case 'GET /reviews':
        return json({
          'data': [
            {
              'id': 'rev-9',
              'appointment': {'id': 'ap-5'},
              'salon': {'id': 'salon-1'},
              'customer': {'id': 'c1', 'fullName': 'Mariam'},
              'rating': 5,
              'comment': 'Great',
              'status': 'PUBLISHED',
              'salonReply': null,
              'version': 2,
              'createdAt': '2026-11-01T06:00:00Z',
            },
          ],
        });
      case 'POST /reviews/rev-9/reply':
        if (body['version'] != 2) return problem(409, 'VERSION_CONFLICT');
        return json({'id': 'rev-9'});
      case 'POST /auth/refresh':
        refreshes++;
        final old = body['refreshToken'] as String?;
        if (revoked.contains(old)) return problem(401, 'UNAUTHENTICATED');
        final who = refreshOwner[old];
        if (who != null) signedIn = who;
        final t = tokens();
        if (who != null) refreshOwner[t['refreshToken'] as String] = who;
        return json(t);
      case 'POST /auth/logout':
        return http.Response('', 204);
      case 'GET /me':
        return json(users[signedIn]!.$2);
      case 'GET /me/salons':
        return json([
          {
            'salon': {'id': 'salon-1', 'code': 'HS-000001', 'name': 'Shape Salon', 'status': 'ACTIVE', 'city': 'Lahore', 'phone': '+92 300 1234567'},
            'role': 'SALON_OWNER',
            'branchIds': [],
            'permissions': [],
          },
        ]);
      case 'GET /discover/salons':
        return json({
          'data': [salonJson],
          'meta': {'page': 1, 'pageSize': 100, 'total': 1, 'totalPages': 1},
        });
      case 'GET /unused':
        return json({
          'data': [
            {
              'id': 'salon-1',
              'name': 'Shape Salon',
              'description': 'Colour studio',
              'city': 'Lahore',
              'branches': [
                {
                  'id': 'br-1',
                  'name': 'Main branch',
                  'addressLine': '12 Main Blvd',
                  'area': 'Gulberg',
                  'city': 'Lahore',
                  'phone': '+92 300 1234567',
                  'hours': [
                    {'weekday': 0, 'closed': false, 'opens': '12:00', 'closes': '18:00'},
                    {'weekday': 1, 'closed': false, 'opens': '10:00', 'closes': '20:00'},
                  ],
                },
              ],
            },
          ],
          'meta': {'page': 1, 'pageSize': 100, 'total': 1, 'totalPages': 1},
        });
      case 'GET /discover/branches/br-1/menu':
        return json({
          'branchId': 'br-1',
          'services': [
            {'id': 'svc-1', 'name': 'Root colour', 'category': 'Colour', 'price': '2500.00', 'durationMin': 90},
          ],
          'staff': [
            {'id': 'mem-1', 'fullName': 'Noor Fatima', 'title': 'Senior Stylist', 'specialties': [], 'avatarFileId': null},
          ],
        });
      case 'PUT /me/favourites/salon-1':
        return http.Response('', 204);
    }
    return problem(404, 'NOT_FOUND');
  });
}

void main() {
  late FakeHola hola;
  late HolaApi api;
  late LocalDatabase db;
  late LocalAuthRepository auth;
  late LocalSalonRepository salons;
  late LocalBookingRepository bookings;
  const pw = 'secret-pass-1';

  setUp(() async {
    hola = FakeHola();
    api = HolaApi(client: hola.client, tokens: MemoryTokenStore(), base: 'https://test/api/v1');
    db = LocalDatabase(MemoryStorage());
    auth = LocalAuthRepository(db, api: api);
    salons = LocalSalonRepository(db, api: api);
    bookings = LocalBookingRepository(db, api: api);
    await auth.init();
  });

  test('customer signs up on the server and is signed in', () async {
    final a = await auth.signUp(role: Role.customer, name: 'Mariam Siddiqui', email: 'Mariam@Example.com', phone: '0300 111 2233', password: pw);
    expect(hola.calls, containsAllInOrder(['POST /auth/register', 'GET /me']));
    expect(a.role, Role.customer);
    expect(a.email, 'mariam@example.com');
    expect(auth.current?.id, 'cust-0'); // the server's id
    expect(await api.hasSession, isTrue);
  });

  test('server errors land on the right field', () async {
    await auth.signUp(role: Role.customer, name: 'Mariam', email: 'm@x.pk', phone: '0300 1112233', password: pw);
    await auth.signOut();
    await expectLater(auth.signUp(role: Role.customer, name: 'Mariam', email: 'm@x.pk', phone: '0300 1112233', password: pw), throwsA(isA<DomainError>().having((e) => e.field, 'field', 'email')));
    await expectLater(auth.signIn('m@x.pk', 'wrong-password'), throwsA(isA<DomainError>().having((e) => e.field, 'field', 'password')));
    expect(auth.current, isNull);
    expect(await api.hasSession, isFalse);
  });

  test('sign-in is checked by the server; phone-only accounts no longer work', () async {
    hola.users['noor@salon.pk'] = (
      pw,
      {
        'id': 'owner-1',
        'kind': 'SALON',
        'email': 'noor@salon.pk',
        'fullName': 'Noor Fatima',
        'phone': null,
        'roles': [
          {'role': 'SALON_OWNER', 'scopeId': 'salon-1', 'branchIds': []},
        ],
        'createdAt': '2026-11-02T06:00:00Z',
      },
    );
    final a = await auth.signIn('noor@salon.pk', pw);
    expect(a.role, Role.salonOwner);
    expect(a.salonId, 'salon-1');
    expect(salons.salon('salon-1')!.isActive, isTrue);
    await auth.signOut();
    expect(hola.calls.last, 'POST /auth/logout');
    expect(await api.hasSession, isFalse);
    // Salon sign-up waits for the server endpoint; officers and riders only sign in.
    expect(() => auth.signUp(role: Role.salonOwner, name: 'Rabia', email: 'r@x.pk', phone: '0300 1112233', password: pw), throwsA(isA<DomainError>()));
  });

  test('HOLA staff map to the officer and rider experiences', () async {
    hola.users['officer@hola.pk'] = (
      pw,
      {
        'id': 'emp-1',
        'kind': 'EMPLOYEE',
        'email': 'officer@hola.pk',
        'fullName': 'Bilal Ahmed',
        'roles': [
          {'role': 'SALES_OFFICER', 'scopeId': null, 'branchIds': []},
        ],
        'createdAt': '2026-11-02T06:00:00Z',
      },
    );
    hola.users['admin@hola.pk'] = (
      pw,
      {
        'id': 'emp-2',
        'kind': 'EMPLOYEE',
        'email': 'admin@hola.pk',
        'fullName': 'Admin',
        'roles': [
          {'role': 'SUPER_ADMIN', 'scopeId': null, 'branchIds': []},
        ],
        'createdAt': '2026-11-02T06:00:00Z',
      },
    );
    expect((await auth.signIn('officer@hola.pk', pw)).role, Role.salesOfficer);
    await auth.signOut();
    await expectLater(auth.signIn('admin@hola.pk', pw), throwsA(isA<DomainError>()));
    expect(auth.current, isNull);
  });

  test('an expired access token is refreshed once, even for parallel requests', () async {
    hola.users['m@x.pk'] = (pw, {'id': 'c1', 'kind': 'CUSTOMER', 'email': 'm@x.pk', 'fullName': 'Mariam', 'roles': [], 'createdAt': '2026-11-02T06:00:00Z'});
    hola.accessExpired = true;
    await auth.signIn('m@x.pk', pw); // GET /me needs a refresh first
    expect(hola.refreshes, 1);
    hola.accessExpired = false;
    await Future.wait([api.get('/me'), api.get('/me'), api.get('/me')]);
    expect(hola.refreshes, 1);
  });

  test('HOLA live salons appear for customers with hours and menu', () async {
    hola.users['m@x.pk'] = (pw, {'id': 'c1', 'kind': 'CUSTOMER', 'email': 'm@x.pk', 'fullName': 'Mariam', 'roles': [], 'createdAt': '2026-11-02T06:00:00Z'});
    await auth.signIn('m@x.pk', pw);
    await salons.syncDirectory();
    final s = salons.discover().single;
    expect(s.name, 'Shape Salon');
    expect(s.hola, isTrue);
    expect(s.phone, '+92 300 1234567');
    final b = salons.branches(s.id).single;
    expect(b.address, '12 Main Blvd');
    expect(b.hours[6]!.start, 12 * 60); // server weekday 0 is Sunday
    expect(b.hours[0]!.end, 20 * 60); // Monday
    expect(b.hours[1], isNull); // no hours sent: closed
    final svc = salons.services(s.id).single;
    expect((svc.name, svc.price, svc.durationMin), ('Root colour', 2500, 90));
    // Saving it goes to the HOLA account.
    expect(await salons.toggleFavourite(s.id), isTrue);
    expect(hola.calls.last, 'PUT /me/favourites/salon-1');
  });

  test('a salon signs up in the app and is live on HOLA at once', () async {
    final a = await auth.signUp(
      role: Role.salonOwner,
      name: 'Noor Fatima',
      email: 'noor@salon.pk',
      phone: '0300 1112233',
      password: pw,
      city: 'Lahore',
      salon: const SalonDraft(name: 'Shape Salon', address: '12 Main Blvd', area: 'Gulberg'),
    );
    expect(hola.calls, containsAllInOrder(['POST /auth/register-salon', 'GET /me', 'GET /me/salons', 'GET /discover/salons/salon-1']));
    expect(hola.registeredSalon!['name'], 'Shape Salon');
    expect((hola.registeredSalon!['mainBranch'] as Map)['city'], 'Lahore');
    expect(a.role, Role.salonOwner);
    expect(a.salonId, 'salon-1');
    expect(salons.branches('salon-1').single.address, '12 Main Blvd');
    // A salon needs its name.
    await auth.signOut();
    await expectLater(
      auth.signUp(role: Role.salonOwner, name: 'Rabia', email: 'r@x.pk', phone: '0300 1112233', password: pw, city: 'Lahore'),
      throwsA(isA<DomainError>().having((e) => e.field, 'field', 'salonName')),
    );
  });

  test('a customer books a HOLA salon on the server, sees it, and cancels it', () async {
    hola.users['m@x.pk'] = (pw, {'id': 'c1', 'kind': 'CUSTOMER', 'email': 'm@x.pk', 'fullName': 'Mariam', 'roles': [], 'createdAt': '2026-11-02T06:00:00Z'});
    await auth.signIn('m@x.pk', pw);
    await salons.syncDirectory();
    expect(salons.staff('salon-1').single.accountId, 'mem-1'); // stylist from the menu
    final day = DateTime(2026, 11, 3);
    await bookings.loadAvailability(branchId: 'br-1', serviceIds: ['svc-1'], from: day, days: 2);
    final slot = bookings.availability(branchId: 'br-1', serviceIds: ['svc-1'], day: day).single;
    expect(slot.start, DateTime.parse('2026-11-03T05:00:00Z').toLocal());
    expect(slot.staffIds, ['mem-1']);
    expect(bookings.availability(branchId: 'br-1', serviceIds: ['svc-1'], day: DateTime(2026, 11, 4)), isEmpty);

    final a = await bookings.book(salonId: 'salon-1', branchId: 'br-1', serviceIds: ['svc-1'], staffId: 'mem-1', start: slot.start);
    expect(hola.idempotencyKeys.single, isNotEmpty);
    expect(a.hola, isTrue);
    expect((a.code, a.status, a.price, a.durationMin, a.staffId), ('HB-000001', ApptStatus.requested, 2500, 90, 'mem-1'));
    expect(bookings.forCustomer('c1').single.id, 'ap-1');

    await bookings.cancel(a.id, 'Plans changed');
    expect(bookings.appointment('ap-1')!.status, ApptStatus.cancelledByCustomer);
  });

  test('a taken slot gives a clear message; bookings sync from the server', () async {
    hola.users['m@x.pk'] = (pw, {'id': 'c1', 'kind': 'CUSTOMER', 'email': 'm@x.pk', 'fullName': 'Mariam', 'roles': [], 'createdAt': '2026-11-02T06:00:00Z'});
    await auth.signIn('m@x.pk', pw);
    await salons.syncDirectory();
    hola.slotTaken = true;
    await expectLater(
      bookings.book(salonId: 'salon-1', branchId: 'br-1', serviceIds: ['svc-1'], start: DateTime.parse('2026-11-03T05:00:00Z').toLocal()),
      throwsA(isA<DomainError>().having((e) => e.message, 'message', contains('took that time'))),
    );
    hola.appts['ap-9'] = hola.appt('ap-9', '2026-11-04T06:00:00Z', 'CONFIRMED');
    await bookings.sync();
    expect(bookings.appointment('ap-9')!.status, ApptStatus.confirmed);
  });

  test('salon calendar asks with ISO date-times and reads every page', () async {
    hola.users['noor@salon.pk'] = (
      pw,
      {
        'id': 'owner-1',
        'kind': 'SALON',
        'email': 'noor@salon.pk',
        'fullName': 'Noor',
        'roles': [
          {'role': 'SALON_OWNER', 'scopeId': 'salon-1', 'branchIds': []},
        ],
        'createdAt': '2026-11-02T06:00:00Z',
        'version': 3,
      },
    );
    await auth.signIn('noor@salon.pk', pw);
    await bookings.sync();
    final q = hola.queries['/salons/salon-1/appointments']!;
    expect(q['from'], matches(RegExp(r'^\d{4}-\d\d-\d\dT00:00:00[+-]\d\d:\d\d$')));
    expect(bookings.forSalon('salon-1').map((a) => a.id), containsAll(['ap-1', 'ap-2']));
    await bookings.confirm('ap-1');
    expect(bookings.appointment('ap-1')!.status, ApptStatus.confirmed);
    // Declining needs a reason for the client.
    expect(() => bookings.decline('ap-2', ''), throwsA(isA<DomainError>()));
  });

  test('profile, password, reset link and account deletion go to the server', () async {
    hola.users['m@x.pk'] = (pw, {'id': 'c1', 'kind': 'CUSTOMER', 'email': 'm@x.pk', 'fullName': 'Mariam', 'phone': null, 'roles': [], 'createdAt': '2026-11-02T06:00:00Z', 'version': 3});
    await auth.signIn('m@x.pk', pw);
    await auth.updateProfile(name: 'Mariam Siddiqui', phone: '0300 111 2233', city: 'Lahore');
    expect(hola.bodies['PATCH /me'], {'fullName': 'Mariam Siddiqui', 'phone': '03001112233', 'version': 3});
    expect(auth.current!.name, 'Mariam Siddiqui');
    await expectLater(auth.changePassword('wrong-one-1', 'new-pass-123'), throwsA(isA<DomainError>().having((e) => e.field, 'field', 'current')));
    await auth.changePassword(pw, 'new-pass-123');
    await auth.requestPasswordReset('m@x.pk');
    expect(hola.calls, contains('POST /auth/password/forgot'));
    await expectLater(auth.deleteAccount('nope-nope-1'), throwsA(isA<DomainError>()));
    await auth.deleteAccount(pw);
    expect(auth.current, isNull);
    expect(await api.hasSession, isFalse);
  });

  test('a review of a HOLA visit is sent to HOLA and stays private until checked', () async {
    hola.users['m@x.pk'] = (pw, {'id': 'c1', 'kind': 'CUSTOMER', 'email': 'm@x.pk', 'fullName': 'Mariam', 'roles': [], 'createdAt': '2026-11-02T06:00:00Z'});
    await auth.signIn('m@x.pk', pw);
    hola.appts['ap-5'] = hola.appt('ap-5', '2026-10-30T06:00:00Z', 'COMPLETED');
    await bookings.sync();
    final engage = LocalEngagementRepository(db, api: api);
    final r = await engage.addReview(appointmentId: 'ap-5', stars: 5, text: 'Lovely colour');
    expect(hola.bodies['POST /reviews'], {'appointmentId': 'ap-5', 'rating': 5, 'comment': 'Lovely colour'});
    expect(r.pending, isTrue);
    expect(engage.reviewsForSalon('salon-1'), isEmpty);
    expect(engage.reviewForAppointment('ap-5')!.id, 'rev-1');
  });

  test('a HOLA salon’s hours, owner stylist and catalogue services are saved on the server', () async {
    hola.users['noor@salon.pk'] = (
      pw,
      {
        'id': 'owner-1',
        'kind': 'SALON',
        'email': 'noor@salon.pk',
        'fullName': 'Noor',
        'roles': [
          {'role': 'SALON_OWNER', 'scopeId': 'salon-1', 'branchIds': []},
        ],
        'createdAt': '2026-11-02T06:00:00Z',
      },
    );
    await auth.signIn('noor@salon.pk', pw);
    // Signing in makes the owner the first bookable stylist and loads the team.
    expect(hola.ownerBookable, isTrue);
    expect(hola.bodies['PUT /salons/salon-1/staff/mem-1/schedule']!['shifts'], isNotEmpty);
    expect(salons.staff('salon-1').single.accountId, 'mem-1');
    expect(salons.staff('salon-1').single.week[0]!.start, 10 * 60); // Monday from server weekday 1

    final b = salons.branches('salon-1').single;
    await salons.updateBranch(b.id, name: b.name, address: b.address, area: b.area, city: b.city, hours: [for (var i = 0; i < 7; i++) i == 6 ? null : const Shift(9 * 60, 21 * 60)]);
    final days = (hola.bodies['PUT /salons/salon-1/branches/br-1/hours']!['days'] as List).cast<Map>();
    expect(days.first, {'weekday': 0, 'closed': true}); // Sunday
    expect(days[1], {'weekday': 1, 'closed': false, 'opens': '09:00', 'closes': '21:00'});

    await salons.saveService(salonId: 'salon-1', name: 'root colour', category: 'Colour', description: '', price: 3000, durationMin: 75);
    expect(hola.bodies['POST /salons/salon-1/branches/br-1/services'], {'serviceId': 'cat-1', 'price': '3000', 'durationMin': 75});
    // The salon's own service.
    await salons.saveService(salonId: 'salon-1', name: 'Bridal makeup', category: 'Bridal', description: 'Full look', price: 30000, durationMin: 180);
    expect(hola.bodies['POST /salons/salon-1/branches/br-1/services'], {'name': 'Bridal makeup', 'category': 'Bridal', 'description': 'Full look', 'price': '30000', 'durationMin': 180});
    // Profile, branch details and auto-confirm carry the server version.
    await salons.updateSalon('salon-1', name: 'Shape Salon', phone: '0300 1234567', about: 'Colour studio');
    expect(hola.bodies['PATCH /salons/salon-1'], {'name': 'Shape Salon', 'phone': '03001234567', 'description': 'Colour studio', 'version': 7});
    expect(hola.bodies['PATCH /salons/salon-1/branches/br-1']!['version'], 2);
    // Photos: an existing HOLA photo keeps its id; the list is replaced in order.
    await salons.setSalonPhotos('salon-1', ['https://test/api/v1/public/files/old-1']);
    expect(hola.bodies['PUT /salons/salon-1/photos'], {
      'fileIds': ['old-1'],
    });
    expect(salons.salon('salon-1')!.cover, 'https://test/api/v1/public/files/old-1');
    // A team member by name only: no email, bookable, given the opening hours.
    final ayesha = await salons.addStaff('salon-1', name: 'Ayesha Malik', title: 'Stylist');
    expect(hola.bodies['POST /salons/salon-1/staff'], {'fullName': 'Ayesha Malik', 'title': 'Stylist', 'bookable': true});
    expect((hola.bodies['PUT /salons/salon-1/staff/mem-2/schedule']!['shifts'] as List), isNotEmpty);
    expect(ayesha.id, 'mem-2');
    expect(salons.staff('salon-1').map((p) => p.accountId), containsAll(['mem-1', 'mem-2']));
  });

  test('complaints and review replies go through the server', () async {
    // HOLA removed complaints in 0.30.0; this keeps the server path covered.
    LocalEngagementRepository.complaintsLive = true;
    addTearDown(() => LocalEngagementRepository.complaintsLive = false);
    hola.users['m@x.pk'] = (pw, {'id': 'c1', 'kind': 'CUSTOMER', 'email': 'm@x.pk', 'fullName': 'Mariam', 'roles': [], 'createdAt': '2026-11-02T06:00:00Z'});
    await auth.signIn('m@x.pk', pw);
    await salons.syncDirectory();
    final engage = LocalEngagementRepository(db, api: api);
    await engage.raiseComplaint(salonId: 'salon-1', topic: 'Waiting time', text: 'Waited 30 minutes past my time.');
    expect(hola.bodies['POST /complaints'], {'category': 'SERVICE', 'subject': 'Waiting time', 'description': 'Waited 30 minutes past my time.', 'salonId': 'salon-1'});
    await engage.sync();
    expect(engage.complaintsForCustomer('c1').single.response, 'Sorry, we added a stylist.');
    await auth.signOut();

    hola.users['noor@salon.pk'] = (
      pw,
      {
        'id': 'owner-1',
        'kind': 'SALON',
        'email': 'noor@salon.pk',
        'fullName': 'Noor',
        'roles': [
          {'role': 'SALON_OWNER', 'scopeId': 'salon-1', 'branchIds': []},
        ],
        'createdAt': '2026-11-02T06:00:00Z',
      },
    );
    await auth.signIn('noor@salon.pk', pw);
    await engage.sync();
    await engage.resolveComplaint('cmp-1', 'We are sorry, it will not happen again.');
    expect(hola.bodies['POST /complaints/cmp-1/messages'], {'body': 'We are sorry, it will not happen again.'});
    final r = engage.reviewsForSalon('salon-1').single;
    await engage.replyToReview(r.id, 'Thank you, Mariam!');
    expect(hola.bodies['POST /reviews/rev-9/reply'], {'reply': 'Thank you, Mariam!', 'version': 2});
  });

  test('a photo uploads in two steps with matching type and size', () async {
    hola.users['noor@salon.pk'] = (
      pw,
      {
        'id': 'owner-1',
        'kind': 'SALON',
        'email': 'noor@salon.pk',
        'fullName': 'Noor',
        'roles': [
          {'role': 'SALON_OWNER', 'scopeId': 'salon-1', 'branchIds': []},
        ],
        'createdAt': '2026-11-02T06:00:00Z',
      },
    );
    hola.calls.clear();
    await api.login('noor@salon.pk', pw);
    // A JPEG starts FF D8 FF; the rest is filler.
    final jpeg = [0xFF, 0xD8, 0xFF, ...List.filled(1231, 7)];
    // Not a photo (no image signature): refused before anything is sent.
    await expectLater(api.uploadFile(List.filled(1234, 7), contentType: 'image/jpeg', purpose: 'salon_photo'), throwsA(isA<DomainError>()));
    final id = await api.uploadFile(jpeg, contentType: 'image/jpeg', purpose: 'salon_photo', fileName: 'front.jpg');
    expect(id, 'file-1');
    expect(hola.bodies['POST /files'], {'purpose': 'salon_photo', 'contentType': 'image/jpeg', 'sizeBytes': 1234, 'fileName': 'front.jpg'});
    expect(hola.uploaded, ('image/jpeg', 1234));
  });

  test('saving hours twice in a row works (fresh version each time); empty address fields aren’t sent', () async {
    hola.users['noor@salon.pk'] = (
      pw,
      {
        'id': 'owner-1',
        'kind': 'SALON',
        'email': 'noor@salon.pk',
        'fullName': 'Noor',
        'roles': [
          {'role': 'SALON_OWNER', 'scopeId': 'salon-1', 'branchIds': []},
        ],
        'createdAt': '2026-11-02T06:00:00Z',
      },
    );
    await auth.signIn('noor@salon.pk', pw);
    final week = [for (var i = 0; i < 7; i++) i == 6 ? null : const Shift(11 * 60, 19 * 60)];
    await salons.updateStaff('mem-1', title: 'Owner', bookable: true, week: week);
    await salons.updateStaff('mem-1', title: 'Senior stylist', bookable: true, week: week);
    expect(hola.memberVersion, 7); // sign-in + two saves, none rejected
    final b = salons.branches('salon-1').single;
    await salons.updateBranch(b.id, name: 'Main branch', address: '12 Main Blvd', area: '', city: 'Lahore', hours: b.hours);
    expect(hola.bodies['PATCH /salons/salon-1/branches/br-1']!.containsKey('area'), isFalse);
  });

  test('the owner never ends up bookable with no working hours', () async {
    // A salon set up before opening hours: the owner was bookable but had no shifts.
    hola.ownerBookable = true;
    hola.users['noor@salon.pk'] = (
      pw,
      {
        'id': 'owner-1',
        'kind': 'SALON',
        'email': 'noor@salon.pk',
        'fullName': 'Noor',
        'roles': [
          {'role': 'SALON_OWNER', 'scopeId': 'salon-1', 'branchIds': []},
        ],
        'createdAt': '2026-11-02T06:00:00Z',
      },
    );
    await auth.signIn('noor@salon.pk', pw);
    expect(hola.ownerShifts, isNotEmpty); // repaired with the opening hours
    expect(hola.ownerShifts.every((s) => s['branchId'] == 'br-1'), isTrue);
    // Saving "takes bookings" with every day off is refused instead of emptying the schedule.
    await expectLater(salons.updateStaff('mem-1', title: 'Owner', bookable: true, week: List.filled(7, null)), throwsA(isA<DomainError>()));
    expect(hola.ownerShifts, isNotEmpty);
  });

  test('the customer is told when the salon confirms; the salon when a request arrives', () async {
    hola.users['m@x.pk'] = (pw, {'id': 'c1', 'kind': 'CUSTOMER', 'email': 'm@x.pk', 'fullName': 'Mariam', 'roles': [], 'createdAt': '2026-11-02T06:00:00Z'});
    await auth.signIn('m@x.pk', pw);
    final engage = LocalEngagementRepository(db, api: api);
    hola.appts['ap-1'] = hola.appt('ap-1', '2026-11-03T06:00:00Z', 'REQUESTED');
    await bookings.sync(); // first sync fills the list quietly
    expect(engage.notifications().where((n) => n.title == 'Booking confirmed'), isEmpty);
    hola.appts['ap-1'] = hola.appt('ap-1', '2026-11-03T06:00:00Z', 'CONFIRMED');
    await bookings.sync();
    expect(bookings.appointment('ap-1')!.status, ApptStatus.confirmed);
    final n = engage.notifications().firstWhere((n) => n.title == 'Booking confirmed');
    expect(n.args['salon'], 'Shape Salon');
    expect(n.link?.id, 'ap-1');
  });

  test('fingerprint sign-in is kept per account; password sign-in still switches accounts', () async {
    final fp = MemoryFingerprintStore();
    final store = MemoryTokenStore();
    api = HolaApi(client: hola.client, tokens: store, base: 'https://test/api/v1');
    auth = LocalAuthRepository(db, api: api, fingerprints: fp);
    await auth.init();
    hola.users['m@x.pk'] = (pw, {'id': 'c1', 'kind': 'CUSTOMER', 'email': 'm@x.pk', 'fullName': 'Mariam Khan', 'roles': [], 'createdAt': '2026-11-02T06:00:00Z'});
    hola.users['r@hola.pk'] = (
      pw,
      {
        'id': 'rd1',
        'kind': 'EMPLOYEE',
        'email': 'r@hola.pk',
        'fullName': 'Arslan',
        'roles': [
          {'role': 'DELIVERY_RIDER', 'scopeId': null, 'branchIds': []},
        ],
        'permissions': ['deliveries.own'],
        'createdAt': '2026-11-02T06:00:00Z',
      },
    );

    // Customer turns it on and signs out: the session is kept, not ended.
    await auth.signIn('m@x.pk', pw);
    await auth.enableFingerprint();
    hola.calls.clear();
    await auth.signOut();
    expect(hola.calls, isNot(contains('POST /auth/logout')));
    expect(auth.resumable.map((f) => f.accountId), ['c1']);

    // The rider signs in with a password on the same phone; the customer's
    // fingerprint sign-in is untouched. The rider turns theirs on too.
    final rider = await auth.signIn('r@hola.pk', pw);
    expect(rider.role, Role.rider);
    expect(auth.fingerprintOn('c1'), isTrue);
    await auth.enableFingerprint();
    await auth.signOut();
    expect(auth.resumable.map((f) => f.accountId).toSet(), {'c1', 'rd1'});
    expect(auth.resumable.firstWhere((f) => f.accountId == 'rd1').role, 'rider');

    // Each fingerprint brings back its own account.
    expect((await auth.resumeWithFingerprint('c1')).id, 'c1');
    expect(auth.resumable, isEmpty); // someone is signed in
    await auth.signOut();
    expect((await auth.resumeWithFingerprint('rd1')).id, 'rd1');
    await auth.signOut();

    // Survives a restart of the app.
    final again = LocalAuthRepository(
      db,
      api: HolaApi(client: hola.client, tokens: store, base: 'https://test/api/v1'),
      fingerprints: fp,
    );
    await again.init();
    expect(again.resumable.length, 2);

    // Turning one off leaves the other.
    await auth.resumeWithFingerprint('c1');
    await auth.disableFingerprint();
    await auth.signOut();
    expect(hola.calls.last, 'POST /auth/logout'); // off: a real sign-out
    expect(auth.resumable.map((f) => f.accountId), ['rd1']);

    // HOLA ended the rider's session: fingerprint asks for the password again.
    hola.revoked.add((await store.readParked('rd1'))!.refresh);
    await expectLater(auth.resumeWithFingerprint('rd1'), throwsA(isA<DomainError>()));
    expect(auth.fingerprintOn('rd1'), isFalse);
    expect(auth.resumable, isEmpty);
    expect(auth.current, isNull);
  });
}
