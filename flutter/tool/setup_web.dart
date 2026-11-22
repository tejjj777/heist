import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi_web/src/setup/setup_common.dart';

Future<void> main() async {
  final build = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'js',
    '-O2',
    'tool/sqlite_worker.dart',
    '-o',
    'web/sqflite_sw.js',
  ]);
  stdout.write(build.stdout);
  stderr.write(build.stderr);
  if (build.exitCode != 0) exit(build.exitCode);
  final uri = Uri.parse('$sqlite3WasmReleaseUri');
  final response = await http.get(uri).timeout(const Duration(seconds: 60));
  if (response.statusCode != 200 || response.bodyBytes.length < 10000)
    throw StateError('SQLite WASM download failed (${response.statusCode}).');
  await File('web/sqlite3.wasm').writeAsBytes(response.bodyBytes, flush: true);
  stdout.writeln('SQLite worker and WASM are ready for web.');
}
