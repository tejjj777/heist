import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:heist_flutter/data/local_store.dart';

void main() {
  late Database db;
  late Box<String> recovery;
  late Box<dynamic> prefs;
  late LocalStore store;
  late Directory directory;
  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('heist_test_');
    Hive.init(directory.path);
    recovery = await Hive.openBox<String>('recovery');
    prefs = await Hive.openBox<dynamic>('preferences');
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    store = LocalStore(db, recovery, prefs);
    await store.load();
  });
  tearDown(() async {
    store.dispose();
    if (db.isOpen) await db.close();
    await Hive.close();
  });

  test('concurrent writes serialize without losing records', () async {
    await Future.wait(
      List.generate(
        25,
        (i) => store.put('budget.expenses', {
          'id': 'e$i',
          'amount': i + 1,
          'date': '2026-11-21',
          'categoryId': 'food',
        }),
      ),
    );
    expect(store.collection('budget.expenses').length, 25);
    expect((await store.history()).length, 20);
    expect(recovery.length, 10);
    final reopened = LocalStore(db, recovery, prefs);
    await reopened.load();
    expect(reopened.collection('budget.expenses').length, 25);
  });

  test(
    'Hive language privacy and tutorial survive a full storage reopen',
    () async {
      await store.setPreference('language', 'te');
      await store.setPreference('hideAmounts', true);
      await store.setPreference('tutorial.v1', true);
      await prefs.close();
      final reopenedPrefs = await Hive.openBox<dynamic>('preferences');
      final reopened = LocalStore(db, recovery, reopenedPrefs);
      await reopened.load();
      expect(reopened.language, 'te');
      expect(reopened.hideAmounts, true);
      expect(reopenedPrefs.get('tutorial.v1'), true);
      reopened.dispose();
    },
  );
  test(
    'corrupt latest SQL revision recovers previous valid document',
    () async {
      await store.mutate((s) => s['currency'] = 'USD');
      await db.insert('snapshots', {
        'created_at': 'bad',
        'document': '{broken',
      });
      final recovered = LocalStore(db, recovery, prefs);
      await recovered.load();
      expect(recovered.state['currency'], 'USD');
      expect(recovered.warning, contains('Recovered'));
    },
  );
  test('Hive restores an empty SQLite database', () async {
    await store.mutate((s) => s['currency'] = 'EUR');
    await db.delete('snapshots');
    final recovered = LocalStore(db, recovery, prefs);
    await recovered.load();
    expect(recovered.state['currency'], 'EUR');
    expect(await db.query('snapshots'), isNotEmpty);
  });
  test(
    'cloud pause after restore does not disable offline recurring payments',
    () async {
      await store.mutate((s) {
        s['recurring'] = [
          {
            'id': 'bill',
            'name': 'Rent',
            'amount': 100,
            'start': '2026-11-01',
            'freq': 'monthly',
            'categoryId': s['budget']['categories'][0]['id'],
            'active': true,
          },
        ];
      });
      await store.pauseSynchronization(true);
      await store.processScheduled(clock: DateTime(2026, 11, 22));
      expect(store.state['budget']['expenses'].length, 1);
      expect(await store.synchronizationPaused(), true);
      await store.processScheduled(clock: DateTime(2026, 11, 22));
      expect(store.state['budget']['expenses'].length, 1);
    },
  );
  test(
    'first web migration seeds legacy data without replacing existing SQL data',
    () async {
      final legacy = store.exportBackup();
      await db.delete('snapshots');
      await recovery.clear();
      final seeded = LocalStore(db, recovery, prefs);
      await seeded.load(initialBackup: legacy);
      expect(seeded.exportBackup(), legacy);
      await seeded.mutate((s) => s['currency'] = 'USD');
      await seeded.load(initialBackup: legacy);
      expect(seeded.state['currency'], 'USD');
    },
  );
  test(
    'invalid first migration preserves legacy data and creates no replacement',
    () async {
      await db.delete('snapshots');
      await recovery.clear();
      final seeded = LocalStore(db, recovery, prefs);
      await expectLater(
        seeded.load(initialBackup: '{"version":999}'),
        throwsFormatException,
      );
      expect(await db.query('snapshots'), isEmpty);
    },
  );
  test('failed SQL write leaves published state unchanged', () async {
    final before = store.exportBackup();
    await db.execute(
      "CREATE TRIGGER reject_writes BEFORE INSERT ON snapshots BEGIN SELECT RAISE(ABORT, 'disk write failed'); END",
    );
    await expectLater(
      store.mutate((s) => s['currency'] = 'USD'),
      throwsA(anything),
    );
    expect(store.exportBackup(), before);
    await db.execute('DROP TRIGGER reject_writes');
    await store.mutate((s) => s['currency'] = 'GBP');
    expect(store.state['currency'], 'GBP');
  });
  test(
    'restore creates a new revision and invalid import is non-destructive',
    () async {
      final old = store.revision;
      await store.mutate((s) => s['currency'] = 'USD');
      await store.restore(old);
      expect(store.state['currency'], 'INR');
      expect(store.revision, greaterThan(old));
      final before = store.exportBackup();
      expect(() => store.importBackup('{}'), throwsFormatException);
      expect(store.exportBackup(), before);
    },
  );
}
