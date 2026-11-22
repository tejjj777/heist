import 'package:hive_ce/hive.dart';

Future<void> initializeHiveStorage() async {
  Hive.init('heist');
}
