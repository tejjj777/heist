import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as desktop;
import 'package:sqflite_common/sqlite_api.dart';

Future<Database> openHeistDatabase() async {
  final DatabaseFactory factory;
  if (Platform.isWindows || Platform.isLinux) {
    desktop.sqfliteFfiInit();
    factory = desktop.databaseFactoryFfi;
  } else {
    factory = mobile.databaseFactory;
  }
  final directory = Directory(
    p.join((await getApplicationSupportDirectory()).path, 'heist'),
  );
  await directory.create(recursive: true);
  final path = p.join(directory.path, 'heist.sqlite');
  return factory.openDatabase(path, options: OpenDatabaseOptions(version: 1));
}
