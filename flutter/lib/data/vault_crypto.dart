import 'dart:convert';
import 'dart:math';
import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import '../domain/planner.dart';

/// Wire compatible with js/sync.js: base64(nonce[12] || ciphertext || tag[16]).
class VaultCrypto {
  final cipher = AesGcm.with256bits();
  List<int> random(int length) =>
      List.generate(length, (_) => Random.secure().nextInt(256));
  Future<SecretKey> derive(String secret, String salt, int iterations) =>
      Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(secret)),
        nonce: base64Decode(salt),
      );
  Future<String> seal(SecretKey key, List<int> bytes) async {
    final box = await cipher.encrypt(bytes, secretKey: key, nonce: random(12));
    return base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<List<int>> unseal(SecretKey key, String text) async {
    final bytes = base64Decode(text);
    if (bytes.length < 28)
      throw const FormatException('Invalid encrypted envelope.');
    return cipher.decrypt(
      SecretBox(
        bytes.sublist(12, bytes.length - 16),
        nonce: bytes.sublist(0, 12),
        mac: Mac(bytes.sublist(bytes.length - 16)),
      ),
      secretKey: key,
    );
  }

  Future<String> lock(Json data, String key) async => jsonEncode({
    'v': 1,
    'z': 1,
    'c': await seal(
      SecretKey(base64Decode(key)),
      GZipEncoder().encode(utf8.encode(jsonEncode(data))),
    ),
  });
  Future<Json> unlock(String text, String key) async {
    final envelope = jsonDecode(text) as Map;
    if (envelope['v'] != 1 || ![0, 1].contains(envelope['z']))
      throw const FormatException('Unsupported vault envelope.');
    var bytes = await unseal(
      SecretKey(base64Decode(key)),
      envelope['c'] as String,
    );
    if (envelope['z'] == 1)
      bytes = GZipDecoder().decodeBytes(bytes, verify: true);
    return parseBackup(utf8.decode(bytes));
  }

  Future<String> openPass(Json row, String password) async {
    final kdf = row['kdf'] as Map;
    final iterations = (kdf['iter'] as num?)?.toInt() ?? 600000;
    if (iterations < 1000 || iterations > 2000000)
      throw const FormatException('Unsupported key derivation cost.');
    return base64Encode(
      await unseal(
        await derive(password, kdf['salt'] as String, iterations),
        row['key_pass'] as String,
      ),
    );
  }

  String cleanRecovery(String value) => value
      .toUpperCase()
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1')
      .replaceAll(RegExp('[^0-9A-Z]'), '');
  Future<String> openRecovery(Json row, String recovery) async => base64Encode(
    await unseal(
      await derive(
        cleanRecovery(recovery),
        row['kdf']['rsalt'] as String,
        1000,
      ),
      row['key_recovery'] as String,
    ),
  );
  Future<({String key, String recovery, Json fields})> create(
    String password,
  ) async {
    return rewrap(base64Encode(random(32)), password);
  }

  Future<({String key, String recovery, Json fields})> rewrap(
    String existingKey,
    String password,
  ) async {
    final key = base64Decode(existingKey),
        salt = base64Encode(random(16)),
        rsalt = base64Encode(random(16));
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final bits = random(
      20,
    ).map((b) => b.toRadixString(2).padLeft(8, '0')).join();
    final code = List.generate(
      32,
      (i) => alphabet[int.parse(bits.substring(i * 5, i * 5 + 5), radix: 2)],
    ).join();
    final recovery = List.generate(
      8,
      (i) => code.substring(i * 4, i * 4 + 4),
    ).join('-');
    return (
      key: base64Encode(key),
      recovery: recovery,
      fields: {
        'kdf': {'salt': salt, 'rsalt': rsalt, 'iter': 600000},
        'key_pass': await seal(await derive(password, salt, 600000), key),
        'key_recovery': await seal(
          await derive(cleanRecovery(recovery), rsalt, 1000),
          key,
        ),
      },
    );
  }
}
