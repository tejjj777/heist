import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../domain/planner.dart';
import 'sync_engine.dart' show canonical;

class BackupCodec {
  static Future<String> encode(Json state) async {
    final payload = jsonEncode(canonical(state));
    final digest = await Sha256().hash(utf8.encode(payload));
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'heist-backup',
      'backupVersion': 2,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'sha256': base64Encode(digest.bytes),
      'data': state,
    });
  }

  static Future<Json> decode(String text) async {
    if (utf8.encode(text).length > 20 * 1024 * 1024)
      throw const FormatException('Backup exceeds 20 MB.');
    final value = jsonDecode(text);
    if (value is! Map) throw const FormatException('Invalid backup.');
    if (value['format'] != 'heist-backup') return parseBackup(text);
    if (value['backupVersion'] != 2 || value['data'] is! Map)
      throw const FormatException('Unsupported backup version.');
    final digest = await Sha256().hash(
      utf8.encode(jsonEncode(canonical(value['data']))),
    );
    if (base64Encode(digest.bytes) != value['sha256'])
      throw const FormatException(
        'Backup checksum mismatch. No data was changed.',
      );
    return parseBackup(jsonEncode(value['data']));
  }
}
