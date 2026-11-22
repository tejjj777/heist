import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:heist_flutter/data/backend.dart';
import 'package:heist_flutter/data/backup_codec.dart';
import 'package:heist_flutter/data/local_store.dart';
import 'package:heist_flutter/data/sync_engine.dart';
import 'package:heist_flutter/data/vault_crypto.dart';
import 'package:heist_flutter/domain/planner.dart';

class MemoryCredentials implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String input) async {
    value = input;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  late Database database;
  late LocalStore store;
  late HeistBackend backend;
  late SyncEngine sync;
  late Json server;
  final crypto = VaultCrypto();
  final key = base64Encode(List.filled(32, 7));
  var loseResponse = false;
  var uploads = 0;
  setUp(() async {
    sqfliteFfiInit();
    Hive.init((await Directory.systemTemp.createTemp('heist_sync_')).path);
    database = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
    );
    store = LocalStore(
      database,
      await Hive.openBox<String>('recovery'),
      await Hive.openBox<dynamic>('preferences'),
    );
    await store.load();
    server = {'version': 1, 'data': await crypto.lock(store.state, key)};
    uploads = 0;
    loseResponse = false;
    backend = HeistBackend(
      url: 'https://example.test',
      publishableKey: 'test-public-key',
      credentials: MemoryCredentials(),
      client: MockClient((request) async {
        if (request.method == 'GET')
          return http.Response(jsonEncode([server]), 200);
        expect(request.headers['authorization'], 'Bearer test-access');
        if (request.url.queryParameters['version'] != 'eq.${server['version']}')
          return http.Response('[]', 200);
        final body = jsonDecode(request.body) as Map;
        server = {...server, ...body};
        uploads++;
        if (loseResponse) {
          loseResponse = false;
          throw const SocketException('response interrupted');
        }
        return http.Response(jsonEncode([server]), 200);
      }),
    );
    backend.session = {
      'user': {'id': 'test-user'},
      'access_token': 'test-access',
      'refresh_token': 'test-refresh',
      'expires_at': 9999999999,
    };
    backend.dataKey = key;
    await backend.persist();
    await store.bindAccount('test-user', 1);
    sync = SyncEngine(store, backend)..online = false;
    await sync.start(watchConnectivity: false, poll: false);
  });
  tearDown(() async {
    sync.dispose();
    store.dispose();
    await database.close();
    await Hive.close();
  });
  test(
    'offline edits survive restart and upload once after reconnect',
    () async {
      await store.mutate((s) => s['currency'] = 'USD');
      await store.mutate((s) => s['settings']['cashOnHand'] = 500);
      expect(await store.pendingCount('test-user'), 2);
      expect(uploads, 0);
      final reopened = LocalStore(database, store.recovery, store.preferences);
      await reopened.load();
      expect(reopened.state['currency'], 'USD');
      expect(await reopened.pendingCount('test-user'), 2);
      sync.online = true;
      await sync.synchronize(manual: true);
      expect(await store.pendingCount('test-user'), 0);
      expect(uploads, 1);
      expect(
        (await crypto.unlock(server['data'], key))['settings']['cashOnHand'],
        500,
      );
    },
  );
  test(
    'server commit followed by lost response does not duplicate submission',
    () async {
      await store.mutate((s) => s['currency'] = 'EUR');
      loseResponse = true;
      sync.online = true;
      await sync.synchronize(manual: true);
      expect(await store.pendingCount('test-user'), 1);
      await sync.synchronize(manual: true);
      expect(await store.pendingCount('test-user'), 0);
      expect(uploads, 1);
    },
  );
  test(
    'divergent remote version parks both copies until explicit resolution',
    () async {
      await store.mutate((s) => s['currency'] = 'USD');
      final remote = store.state..['currency'] = 'GBP';
      server = {'version': 2, 'data': await crypto.lock(remote, key)};
      sync.online = true;
      await sync.synchronize(manual: true);
      expect(store.state['currency'], 'USD');
      expect(uploads, 0);
      final conflicts = await store.conflicts('test-user');
      expect(conflicts, hasLength(1));
      sync.online = false;
      await sync.resolve(conflicts.first['id'], useRemote: true);
      expect(store.state['currency'], 'GBP');
      expect(await store.pendingCount('test-user'), 0);
    },
  );
  test(
    'versioned backup detects tampering and keeps credentials out',
    () async {
      final backup = await BackupCodec.encode(store.state);
      expect((await BackupCodec.decode(backup))['currency'], 'INR');
      expect(backup, isNot(contains('test-refresh')));
      final tampered = jsonDecode(backup) as Map;
      tampered['data']['currency'] = 'USD';
      await expectLater(
        BackupCodec.decode(jsonEncode(tampered)),
        throwsFormatException,
      );
    },
  );
  test(
    'different account credentials cannot read or upload the bound planner',
    () async {
      final before = store.exportBackup();
      backend.session!['user']['id'] = 'other-user';
      sync.online = true;
      await sync.synchronize(manual: true);
      expect(uploads, 0);
      expect(store.exportBackup(), before);
      expect(sync.error, contains('Choose your planner'));
    },
  );
  test(
    'unbound account cannot synchronize before choosing its planner',
    () async {
      await store.unbindAccount();
      sync.online = true;
      await sync.synchronize(manual: true);
      expect(uploads, 0);
      expect(await store.accountOwner(), isNull);
      expect(sync.error, contains('Choose your planner'));
    },
  );
  test(
    'account selection suspends sync until the explicit choice is complete',
    () async {
      await sync.selectAccount(() async {
        await store.mutate((s) => s['currency'] = 'USD');
        sync.online = true;
        await sync.synchronize(manual: true);
        expect(uploads, 0);
        expect(sync.ready, false);
        sync.online = false;
      });
      sync.online = true;
      await sync.synchronize(manual: true);
      expect(uploads, 1);
      expect(sync.ready, true);
    },
  );
  test('AES-GCM rejects a corrupted encrypted snapshot', () async {
    final envelope = jsonDecode(await crypto.lock(store.state, key)) as Map;
    final bytes = base64Decode(envelope['c']);
    bytes[15] ^= 1;
    envelope['c'] = base64Encode(bytes);
    await expectLater(
      crypto.unlock(jsonEncode(envelope), key),
      throwsA(anything),
    );
  });
}
