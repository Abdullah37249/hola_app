import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/data/local/local_database.dart';
import 'package:hola_professional/data/local/storage.dart';
import 'package:hola_professional/domain/entities/entities.dart';

/// Audit H4: signing out of a HOLA account leaves nothing of it on the phone.
void main() {
  test('wiping keeps device settings and clears account data and caches', () async {
    final db = LocalDatabase(MemoryStorage());
    var cacheCleared = false;
    db.onWipe(() => cacheCleared = true);
    db.prefs['language'] = 'ur';
    db.sessionAccountId = 'a1';
    db.notifications.add(AppNotification(id: 'n1', userId: 'a1', title: 'Hi', body: '', at: DateTime(2026)));
    await db.wipeAccountData();
    expect(db.notifications, isEmpty);
    expect(db.sessionAccountId, isNull);
    expect(db.prefs['language'], 'ur');
    expect(cacheCleared, isTrue);
  });
}
