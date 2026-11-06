import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/data/local/hola_mirror.dart';
import 'package:hola_professional/data/local/local_database.dart';
import 'package:hola_professional/data/local/storage.dart';
import 'package:hola_professional/domain/entities/entities.dart';

/// HOLA's offer and booking shapes (contract 0.20.0) as the phone copies them.
void main() {
  test('a public offer keeps its salon, service, discount and this customer\'s use', () {
    final db = LocalDatabase(MemoryStorage());
    final o = mirrorOffer(db, {
      'id': 'of1',
      'salon': {'id': 's1', 'name': 'Studio Saffron'},
      'service': {'id': 'bs1', 'name': 'Gloss toner', 'price': '4000.00', 'durationMin': 45},
      'discountType': 'FIXED',
      'discountValue': '500.00',
      'startsAt': '2026-11-01T19:00:00.000Z',
      'endsAt': '2026-11-06T19:00:00.000Z',
      'myUsage': 'RESERVED',
      'reservedOn': 'HB-000123',
    });
    expect(o.salonId, 's1');
    expect(o.serviceId, 'bs1');
    expect(o.discountType, DiscountType.amount);
    expect(o.discountOn(4000), 500);
    expect(o.myUse, OfferUse.reserved);
    expect(o.heldOn, 'HB-000123');
    expect(db.offers.single.id, 'of1');
  });

  test('a booking keeps the offer the server applied and the discount', () {
    final db = LocalDatabase(MemoryStorage());
    final a = mirrorAppointment(db, {
      'id': 'ap1',
      'code': 'HB-000124',
      'salon': {'id': 's1', 'name': 'Studio Saffron'},
      'branch': {'id': 'b1', 'name': 'Main'},
      'customer': {'id': 'c1', 'fullName': 'Mariam'},
      'items': [
        {
          'branchServiceId': 'bs1',
          'name': 'Gloss toner',
          'originalPrice': '4000.00',
          'discount': '500.00',
          'price': '3500.00',
          'offer': {'id': 'of1', 'discountText': 'Rs 500 off'},
        },
        {'branchServiceId': 'bs2', 'name': 'Blow-dry', 'originalPrice': '1500.00', 'discount': '0.00', 'price': '1500.00', 'offer': null},
      ],
      'totalPrice': '5000.00',
      'status': 'REQUESTED',
      'startsAt': '2026-11-05T10:00:00.000Z',
      'endsAt': '2026-11-05T11:30:00.000Z',
    });
    expect(a.offerIds, ['of1']);
    expect(a.discount, 500);
    expect(a.price, 5000);
  });
}
