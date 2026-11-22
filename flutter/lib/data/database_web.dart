import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<Database> openHeistDatabase() => databaseFactoryFfiWeb.openDatabase(
  'heist.sqlite',
  options: OpenDatabaseOptions(version: 1),
);
