import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/core/utils/format.dart';

void main() {
  test('large amounts are shortened; small ones stay exact', () {
    expect(shortNum(0), '0');
    expect(shortNum(950), '950');
    expect(shortNum(999), '999');
    expect(shortNum(1000), '1K');
    expect(shortNum(1500), '1.5K');
    expect(shortNum(4944), '4.9K');
    expect(shortNum(5000), '5K');
    expect(shortNum(10000), '10K');
    expect(shortNum(25000), '25K');
    expect(shortNum(58800), '58.8K');
    expect(shortNum(100000), '100K');
    expect(shortNum(999999), '1M');
    expect(shortNum(1000000), '1M');
    expect(shortNum(8993025), '9M');
    expect(shortNum(2500000), '2.5M');
    expect(shortNum(-6975), '-7K');
    expect(rsShort(58800), 'Rs 58.8K');
    expect(rsShort(800), 'Rs 800');
    expect(rs(4944), 'Rs 4,944'); // bills stay exact
  });
}
