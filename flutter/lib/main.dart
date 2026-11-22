import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:hive_ce/hive.dart';
import 'data/hive_init.dart';
import 'data/database.dart';
import 'data/local_store.dart';
import 'data/backend.dart';
import 'data/sync_engine.dart';
import 'data/group_service.dart';
import 'data/auth_link.dart';
import 'data/legacy_document.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep web semantics available to assistive technology without a hidden opt-in.
  WidgetsBinding.instance.ensureSemantics();
  try {
    final incomingLink = takeIncomingAuthLink();
    await initializeHiveStorage();
    final preferences = await Hive.openBox<dynamic>('preferences');
    final recovery = await Hive.openBox<String>('recovery');
    final database = await openHeistDatabase();
    final store = LocalStore(database, recovery, preferences);
    await store.load(initialBackup: readLegacyDocument());
    await store.processScheduled();
    Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(
        store.processScheduled().catchError((Object error) {
          store.warning =
              'Scheduled payments could not be saved. Reopen the app to retry.';
        }),
      );
    });
    final sync = SyncEngine(store, HeistBackend());
    final groups = GroupService(
      store,
      HeistBackend(
        credentials: SecureCredentials(storageKey: 'heist.groups.v1'),
      ),
    );
    runApp(HeistApp(store: store, sync: sync, groups: groups));
    sync.addListener(() {
      groups.online = sync.online;
    });
    unawaited(
      groups.start().catchError((Object error) {
        groups.error =
            'Group connection could not start. Local group data remains available.';
      }),
    );
    unawaited(
      sync.start(incomingLink: incomingLink).catchError((Object error) {
        sync.error =
            'Synchronization could not start. Local data remains available.';
      }),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SelectableText(
                'HEIST could not open local storage.\nExisting data has been preserved.\nClose and reopen the app.\n\n$error',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
