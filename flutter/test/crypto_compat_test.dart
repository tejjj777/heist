import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:heist_flutter/data/vault_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original JavaScript vault unlocks with passphrase and recovery',
    () async {
      final fixture = jsonDecode(
        await File('test/fixtures/legacy-vault.json').readAsString(),
      );
      final row = Map<String, dynamic>.from(fixture['row']);
      final crypto = VaultCrypto();
      expect(await crypto.openPass(row, fixture['password']), fixture['key']);
      expect(
        await crypto.openRecovery(row, fixture['recovery']),
        fixture['key'],
      );
      final data = await crypto.unlock(row['data'], fixture['key']);
      expect(data['compatibility'], 'original JavaScript ↔ Flutter');
      final rotated = await crypto.rewrap(
        fixture['key'],
        'new-synthetic-test-passphrase',
      );
      expect(
        await crypto.openPass(rotated.fields, 'new-synthetic-test-passphrase'),
        fixture['key'],
      );
      expect(
        await crypto.openRecovery(rotated.fields, rotated.recovery),
        fixture['key'],
      );
      await expectLater(
        crypto.openPass(rotated.fields, fixture['password']),
        throwsA(anything),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
