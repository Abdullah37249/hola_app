import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/core/push/push_service.dart';

void main() {
  test('HOLA push data opens the right screen', () {
    expect(pushLink({'type': 'order', 'id': 'o-1', 'category': 'ORDERS'})?.toJson(), {'type': 'order', 'id': 'o-1'});
    expect(pushLink({'type': 'appointment', 'id': 'a-2'})?.toJson(), {'type': 'appointment', 'id': 'a-2'});
    expect(pushLink({'type': 'training_session', 'id': 't-3'})?.toJson(), {'type': 'training', 'id': 't-3'});
    expect(pushLink({'type': 'complaint', 'id': 'c-4'})?.type, 'complaint');
    expect(pushLink({'type': 'review', 'id': 'r-5'})?.type, 'review');
    expect(pushLink({'type': 'campaign', 'id': 'x'}), isNull);
    expect(pushLink({'type': 'broadcast'}), isNull);
    expect(pushLink({'type': 'test', 'category': 'ACCOUNT'}), isNull);
    expect(pushLink({'type': 'order'}), isNull); // needs an id
    expect(pushLink({}), isNull);
  });
}
