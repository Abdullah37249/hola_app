import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/data/local/local_database.dart';
import 'package:hola_professional/data/local/local_return_repository.dart';
import 'package:hola_professional/data/local/storage.dart';
import 'package:hola_professional/domain/entities/entities.dart';

/// HOLA's return shapes (contract 0.23.0) as the phone copies them.
void main() {
  test('a ReturnView keeps its order, items, offer, pickup and settlement', () {
    final db = LocalDatabase(MemoryStorage());
    final repo = LocalReturnRepository(db);
    final r = repo.mirrorReturn({
      'id': 'r1',
      'code': 'HR-000001',
      'salon': {'id': 's1', 'name': 'Diamond Glamor Saloon'},
      'order': {'id': 'o1', 'code': 'HO-000018', 'paymentMethod': 'COD', 'total': '340.00'},
      'option': 'REFUND',
      'reason': 'EXPIRED',
      'note': 'Expired last month',
      'items': [
        {'orderItemId': 'oi1', 'variantId': 'v1', 'product': 'Cream Activator', 'variant': '10 Volume', 'qty': 1, 'unitPrice': '340.00', 'lineTotal': '340.00'},
      ],
      'amount': '340.00',
      'approvedAmount': '340.00',
      'status': 'COMPLETED',
      'proposal': {'settlement': 'VOUCHER', 'amount': '340.00', 'validUntil': '2027-02-03T19:00:00.000Z', 'note': '', 'proposedAt': '2026-11-05T06:00:00.000Z'},
      'pickup': {
        'rider': {'id': 'u9', 'fullName': 'Arslan'},
        'assignedAt': '2026-11-05T07:00:00.000Z',
        'expectedOn': null,
        'collectedAt': '2026-11-05T09:00:00.000Z',
      },
      'settlement': {
        'type': 'VOUCHER',
        'amount': '340.00',
        'voucher': {'id': 'c1', 'code': 'HV-7Q2K', 'amount': '340.00', 'validUntil': '2027-02-03T19:00:00.000Z', 'status': 'ACTIVE'},
      },
      'conversationId': 'conv1',
      'createdAt': '2026-11-05T05:00:00.000Z',
      'version': 6,
    });
    expect(r.cod, isTrue);
    expect(r.orderCode, 'HO-000018');
    expect(r.items.single.orderItemId, 'oi1');
    expect(r.items.single.name, 'Cream Activator · 10 Volume');
    expect(r.amount, 340);
    expect(r.proposal!.settlement, Settlement.voucher);
    expect(r.pickup!.riderName, 'Arslan');
    expect(r.pickup!.collectedAt, isNotNull);
    expect(r.settlement!.type, SettlementType.voucher);
    expect(r.settlement!.voucher!.code, 'HV-7Q2K');
    expect(r.conversationId, 'conv1');
    expect(r.version, 6);
    expect(db.returns.single.id, 'r1');
  });

  test('the timeline becomes the audit trail; a replacement keeps its order', () {
    final db = LocalDatabase(MemoryStorage());
    final repo = LocalReturnRepository(db);
    final r = repo.mirrorReturn({
      'id': 'r2',
      'code': 'HR-000002',
      'salon': {'id': 's1'},
      'order': {'id': 'o2', 'code': 'HO-000020', 'paymentMethod': 'CREDIT'},
      'option': 'REPLACE',
      'reason': 'DAMAGED',
      'items': const [],
      'status': 'REPLACEMENT_ORDER_CREATED',
      'settlement': {
        'type': 'REPLACEMENT',
        'amount': '1000.00',
        'replacementOrder': {'id': 'o3', 'code': 'HO-000021', 'status': 'PROCESSING'},
      },
      'timeline': [
        {
          'at': '2026-11-05T05:00:00.000Z',
          'actor': {'id': 'u1', 'fullName': 'Fatima', 'side': 'SALON'},
          'action': 'CREATE',
          'from': null,
          'to': 'REQUESTED',
          'note': '',
        },
        {
          'at': '2026-11-05T09:00:00.000Z',
          'actor': {'id': 'u9', 'fullName': 'Arslan', 'side': 'RIDER'},
          'action': 'REPLACEMENT',
          'from': 'PICKUP_ASSIGNED',
          'to': 'REPLACEMENT_ORDER_CREATED',
          'note': '',
        },
      ],
      'createdAt': '2026-11-05T05:00:00.000Z',
    });
    expect(r.cod, isFalse);
    expect(r.outcome, SettlementType.replacement);
    expect(r.settlement!.replacementOrderCode, 'HO-000021');
    expect(r.history.map((h) => h.side), ['SALON', 'RIDER']);
    expect(r.history.last.action, 'REPLACEMENT');
  });
}
