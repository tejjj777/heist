import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

Future<void> initializeHiveStorage() async {
  final directory = Directory(
    '${(await getApplicationSupportDirectory()).path}/heist/cache',
  );
  await directory.create(recursive: true);
  Hive.init(directory.path);
}
