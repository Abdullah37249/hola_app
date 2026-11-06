import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/app/reminder_sync.dart';
import 'package:hola_professional/core/push/reminders.dart';
import 'package:hola_professional/domain/entities/entities.dart';

void main() {
  test('distance between two salons in Sialkot and to Lahore', () {
    const kashmirRoad = GeoFix(32.501445, 74.497827), shahabPura = GeoFix(32.501479, 74.497854), lahore = GeoFix(31.5204, 74.3587);
    expect(distanceKm(kashmirRoad, shahabPura), lessThan(0.01));
    expect(distanceKm(kashmirRoad, lahore), closeTo(110, 5));
  });

  test('directions use the branch GPS point, else its address', () {
    final b = Branch(id: 'b', salonId: 's', name: 'Main', address: '12 Main Blvd', area: 'Gulberg III', city: 'Lahore');
    expect(mapsLink(b, 'Maison Noor'), contains('query=Maison%20Noor%2C%2012%20Main%20Blvd'));
    b.location = const GeoFix(31.52, 74.35);
    expect(mapsLink(b, 'Maison Noor'), 'https://www.google.com/maps/dir/?api=1&destination=31.52,74.35');
  });

  test('the phone\'s reminder and HOLA\'s push for one visit share an id', () {
    expect(Reminders.idFor('ap1', '24h'), Reminders.idFor('ap1', '24h'));
    expect(Reminders.idFor('ap1', '24h'), isNot(Reminders.idFor('ap1', '2h')));
    expect(Reminders.idFor('ap1', '2h'), greaterThanOrEqualTo(0));
  });
}
