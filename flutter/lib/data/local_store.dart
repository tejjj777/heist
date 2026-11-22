import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:sqflite_common/sqlite_api.dart';
import '../domain/planner.dart';
import '../domain/scheduled.dart';

/// SQLite is authoritative. A committed revision is mirrored to Hive afterward.
/// The previous good document is never overwritten in-place as the only backup.
class LocalStore extends ChangeNotifier {
  final Database database;
  final Box<String> recovery;
  final Box<dynamic> preferences;
  Json _state = initialState();
  Json get state => clone(_state);
  int revision = 0;
  String? warning;
  Future<void> _tail = Future<void>.value();
  LocalStore(this.database, this.recovery, this.preferences);

  Future<void> load({String? initialBackup}) async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS snapshots (revision INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL, document TEXT NOT NULL)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS entities (kind TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(kind,id))',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS expenses (id TEXT PRIMARY KEY, date TEXT NOT NULL, category_id TEXT NOT NULL, amount_minor INTEGER NOT NULL CHECK(amount_minor >= 0), note TEXT NOT NULL)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS expenses_date_category ON expenses(date, category_id)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS categories (id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, planned_minor INTEGER NOT NULL)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS goals (id TEXT PRIMARY KEY, name TEXT NOT NULL, target_minor INTEGER NOT NULL, saved_minor INTEGER NOT NULL, deadline TEXT)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS sync_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await database.execute(
      "CREATE TABLE IF NOT EXISTS outbox (operation_id TEXT PRIMARY KEY, owner_uid TEXT NOT NULL, kind TEXT NOT NULL, revision INTEGER NOT NULL, document TEXT NOT NULL, base_version INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_attempt INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'pending', error TEXT)",
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS conflicts (id TEXT PRIMARY KEY, created_at TEXT NOT NULL, owner_uid TEXT NOT NULL, local_document TEXT NOT NULL, remote_document TEXT NOT NULL, remote_version INTEGER NOT NULL)',
    );
    final records = await database.query(
      'snapshots',
      orderBy: 'revision DESC',
      limit: 20,
    );
    for (final record in records) {
      try {
        _state = parseBackup(record['document'] as String);
        revision = record['revision'] as int;
        if (record['revision'] != records.first['revision'])
          warning =
              'Recovered an earlier SQLite revision. Export a backup before continuing.';
        await _mirror(jsonEncode(_state));
        return;
      } catch (e) {
        if (e is! FormatException && e is! TypeError) rethrow;
      }
    }
    final keys = recovery.keys.cast<String>().toList()
      ..sort((a, b) => b.compareTo(a));
    for (final key in keys) {
      try {
        final restored = parseBackup(recovery.get(key)!);
        await _commit(restored);
        warning = 'Recovered data from Hive. Export a backup now.';
        return;
      } catch (e) {
        if (e is! FormatException && e is! TypeError) rethrow;
      }
    }
    if (records.isNotEmpty || keys.isNotEmpty)
      throw const FormatException(
        'No readable recovery revision. Existing files were preserved.',
      );
    if (initialBackup != null) {
      final legacy = parseBackup(initialBackup);
      await _commit(legacy);
      warning =
          'Imported existing HEIST data into SQLite. The original browser data remains unchanged.';
      return;
    }
    await _commit(initialState());
  }

  Future<void> _mirror(String encoded) async {
    try {
      await recovery.put(revision.toString().padLeft(20, '0'), encoded);
      await recovery.flush();
      final keys = recovery.keys.cast<String>().toList()..sort();
      if (keys.length > 10)
        await recovery.deleteAll(keys.take(keys.length - 10));
    } catch (_) {
      warning =
          'Saved to SQLite; Hive recovery copy failed. Export a JSON backup.';
    }
  }

  Future<void> _commit(
    Json next, {
    bool enqueue = true,
    int? remoteVersion,
    String? clearOwner,
    Json? groupOperation,
    String? groupOwner,
  }) async {
    final encoded = jsonEncode(next);
    final committed = await database.transaction<int>((tx) async {
      if (clearOwner != null)
        await tx.delete(
          'outbox',
          where: 'owner_uid = ?',
          whereArgs: [clearOwner],
        );
      final id = await tx.insert('snapshots', {
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'document': encoded,
      });
      await tx.delete('entities');
      await tx.delete('expenses');
      await tx.delete('categories');
      await tx.delete('goals');
      final batch = tx.batch();
      for (final e in rows(next['budget']['expenses'])) {
        batch.insert('expenses', {
          'id': e['id'],
          'date': e['date'],
          'category_id': e['categoryId'] ?? '',
          'amount_minor': (number(e['amount']) * 100).round(),
          'note': e['note'] ?? '',
        });
      }
      for (final c in rows(next['budget']['categories'])) {
        batch.insert('categories', {
          'id': c['id'],
          'name': c['name'] ?? '',
          'type': c['type'] ?? 'wants',
          'planned_minor': (number(c['planned']) * 100).round(),
        });
      }
      for (final g in rows(next['goals'])) {
        batch.insert('goals', {
          'id': g['id'],
          'name': g['name'] ?? '',
          'target_minor': (number(g['target']) * 100).round(),
          'saved_minor': (number(g['saved']) * 100).round(),
          'deadline': g['deadline'],
        });
      }
      for (final path in [
        'budget.categories',
        'budget.expenses',
        'goals',
        'debts',
        'gifts',
        'subscriptions',
        'recurring',
        'wallet.cash',
        'wallet.ious',
        'incomeLog',
        'groups',
        'travelTrips',
      ]) {
        dynamic list = next;
        for (final key in path.split('.')) {
          list = list is Map ? list[key] : null;
        }
        for (final row in rows(list)) {
          batch.insert('entities', {
            'kind': path,
            'id': row['id'],
            'body': jsonEncode(row),
          });
        }
      }
      await batch.commit(noResult: true);
      if (remoteVersion != null)
        await tx.insert('sync_meta', {
          'key': 'version',
          'value': '$remoteVersion',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      final owners = await tx.query(
        'sync_meta',
        where: 'key = ?',
        whereArgs: ['owner'],
      );
      if (enqueue && owners.isNotEmpty && next['meta']['isSample'] != true) {
        final versions = await tx.query(
          'sync_meta',
          where: 'key = ?',
          whereArgs: ['version'],
        );
        final blocked = await tx.query(
          'outbox',
          where: "status = 'conflict'",
          limit: 1,
        );
        await tx.insert('outbox', {
          'operation_id': newId(),
          'owner_uid': owners.first['value'],
          'kind': 'vault',
          'revision': id,
          'document': encoded,
          'base_version': versions.isEmpty
              ? 0
              : int.parse(versions.first['value'] as String),
          'status': blocked.isEmpty ? 'pending' : 'conflict',
        });
      }
      if (groupOperation != null && groupOwner != null) {
        await tx.insert('outbox', {
          'operation_id': groupOperation['operation_id'],
          'owner_uid': groupOwner,
          'kind': 'group',
          'revision': id,
          'document': jsonEncode(groupOperation),
          'base_version': 0,
        });
      }
      await tx.rawDelete(
        'DELETE FROM snapshots WHERE revision NOT IN (SELECT revision FROM snapshots ORDER BY revision DESC LIMIT 20)',
      );
      return id;
    });
    // Publish only after SQL COMMIT: failed writes leave the UI state unchanged.
    _state = next;
    revision = committed;
    await _mirror(encoded);
    notifyListeners();
  }

  Future<void> mutate(void Function(Json) change) {
    return exclusive(() async {
      final next = clone(_state);
      change(next);
      await _commit(parseBackup(jsonEncode(next)));
    });
  }

  Future<void> processScheduled({DateTime? clock}) => exclusive(() async {
    final next = clone(_state);
    if (applyScheduledChanges(next, clock ?? DateTime.now()))
      await _commit(parseBackup(jsonEncode(next)));
  });

  Future<void> exclusive(Future<void> Function() work) {
    final result = _tail.then((_) => work());
    // A failed operation must not poison subsequent queued writes.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> importBackup(String encoded) {
    final next = parseBackup(encoded);
    return mutate((state) {
      state.clear();
      state.addAll(next);
    });
  }

  String exportBackup() => const JsonEncoder.withIndent('  ').convert(_state);
  List<Json> collection(String path) {
    dynamic current = _state;
    for (final key in path.split('.')) {
      current = current is Map ? current[key] : null;
    }
    return rows(current);
  }

  Future<void> put(String path, Json row) => mutate((state) {
    final keys = path.split('.');
    dynamic parent = state;
    for (final key in keys.take(keys.length - 1)) {
      parent[key] ??= <String, dynamic>{};
      parent = parent[key];
    }
    final list = rows(parent[keys.last]);
    final index = list.indexWhere((x) => x['id'] == row['id']);
    if (index == -1) {
      list.add(row);
    } else {
      list[index] = row;
    }
    parent[keys.last] = list;
  });
  Future<void> remove(String path, String id) => mutate((state) {
    final keys = path.split('.');
    dynamic parent = state;
    for (final key in keys.take(keys.length - 1)) {
      parent = parent[key];
    }
    parent[keys.last] = rows(
      parent[keys.last],
    ).where((x) => x['id'] != id).toList();
  });
  Future<void> setDark(bool value) async {
    await preferences.put('dark', value);
    notifyListeners();
  }

  String get language {
    final value = preferences.get('language', defaultValue: 'en');
    return const ['en', 'te', 'hi'].contains(value) ? value as String : 'en';
  }

  bool get hideAmounts =>
      preferences.get(
        'hideAmounts',
        defaultValue: _state['settings']['privacy'] == true,
      ) ==
      true;
  Future<void> _preferenceTail = Future<void>.value();
  Future<void> get preferencesSaved => _preferenceTail;
  Future<void> setPreference(String key, dynamic value) {
    final write = _preferenceTail.then((_) async {
      await preferences.put(key, value);
      await preferences.flush();
      notifyListeners();
    });
    _preferenceTail = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return write;
  }

  Future<void> pauseSynchronization(bool pause) async {
    await exclusive(() async {
      await database.insert('sync_meta', {
        'key': 'paused',
        'value': pause ? 'true' : 'false',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      notifyListeners();
    });
  }

  Future<bool> synchronizationPaused() async {
    final rows = await database.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['paused'],
    );
    return rows.isNotEmpty && rows.first['value'] == 'true';
  }

  Future<List<Json>> pendingSummary() async => (await database.query(
    'outbox',
    columns: [
      'operation_id',
      'kind',
      'revision',
      'attempts',
      'status',
      'error',
    ],
    orderBy: 'revision DESC',
  )).map((r) => Map<String, dynamic>.from(r)).toList();
  Future<void> retryFailed() => exclusive(() async {
    await database.update('outbox', {
      'status': 'pending',
      'next_attempt': 0,
      'error': null,
    }, where: "status = 'failed'");
    notifyListeners();
  });

  bool get dark =>
      preferences.get(
        'dark',
        defaultValue: _state['settings']['dark'] == true,
      ) ==
      true;
  Future<List<Json>> history() async => (await database.query(
    'snapshots',
    orderBy: 'revision DESC',
    limit: 20,
  )).map((r) => Map<String, dynamic>.from(r)).toList();
  Future<void> restore(int id) async {
    final candidates = await database.query(
      'snapshots',
      where: 'revision = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (candidates.isEmpty)
      throw const FormatException('Recovery revision no longer exists.');
    await importBackup(candidates.single['document'] as String);
  }

  Future<void> bindAccount(
    String owner,
    int version, {
    bool uploadLocal = false,
  }) => exclusive(() async {
    final old = await database.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['owner'],
    );
    if (old.isNotEmpty && old.first['value'] != owner)
      throw const FormatException('Sign out before switching accounts.');
    await database.transaction((tx) async {
      await tx.insert('sync_meta', {
        'key': 'owner',
        'value': owner,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.insert('sync_meta', {
        'key': 'version',
        'value': '$version',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    if (uploadLocal) await _commit(clone(_state));
    notifyListeners();
  });
  Future<void> unbindAccount() => exclusive(() async {
    // Keep owner-tagged pending writes for the same account to resume later.
    await database.delete('sync_meta', where: 'key = ?', whereArgs: ['owner']);
    notifyListeners();
  });
  Future<String?> accountOwner() async {
    final records = await database.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['owner'],
    );
    return records.firstOrNull?['value'] as String?;
  }

  Future<int> pendingCount([String? owner]) async =>
      (await database.rawQuery(
            "SELECT COUNT(*) AS n FROM outbox WHERE status != 'acknowledged'${owner == null ? '' : ' AND owner_uid = ?'}",
            owner == null ? [] : [owner],
          )).first['n']
          as int;
  Future<List<Json>> pending(String owner) async => (await database.query(
    'outbox',
    where: "owner_uid = ? AND status != 'acknowledged'",
    whereArgs: [owner],
    orderBy: 'revision DESC',
  )).map((r) => Map<String, dynamic>.from(r)).toList();
  Future<void> groupMutation(
    String owner,
    Json operation,
    void Function(Json) change,
  ) => exclusive(() async {
    final next = clone(_state);
    change(next);
    await _commit(
      parseBackup(jsonEncode(next)),
      groupOperation: operation,
      groupOwner: owner,
    );
  });
  Future<void> acknowledgeGroup(String operationId) => exclusive(() async {
    await database.delete(
      'outbox',
      where: "operation_id = ? AND kind = 'group'",
      whereArgs: [operationId],
    );
    notifyListeners();
  });
  Future<int> remoteVersion() async {
    final r = await database.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['version'],
    );
    return r.isEmpty ? 0 : int.parse(r.first['value'] as String);
  }

  Future<void> acknowledge(String owner, int throughRevision, int version) =>
      exclusive(() async {
        await database.transaction((tx) async {
          await tx.delete(
            'outbox',
            where: "owner_uid = ? AND revision <= ? AND kind = 'vault'",
            whereArgs: [owner, throughRevision],
          );
          await tx.update(
            'outbox',
            {'base_version': version},
            where: "owner_uid = ? AND revision > ? AND kind = 'vault'",
            whereArgs: [owner, throughRevision],
          );
          await tx.insert('sync_meta', {
            'key': 'version',
            'value': '$version',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        });
        notifyListeners();
      });
  Future<bool> acceptRemoteIfClean(
    String owner,
    Json remote,
    int version,
  ) async {
    var accepted = false;
    await exclusive(() async {
      if (await pendingCount(owner) != 0) return;
      await _commit(
        parseBackup(jsonEncode(remote)),
        enqueue: false,
        remoteVersion: version,
      );
      accepted = true;
    });
    return accepted;
  }

  Future<void> parkConflict(String owner, Json remote, int version) =>
      exclusive(() async {
        await database.transaction((tx) async {
          await tx.insert('conflicts', {
            'id': newId(),
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'owner_uid': owner,
            'local_document': jsonEncode(_state),
            'remote_document': jsonEncode(remote),
            'remote_version': version,
          });
          await tx.update(
            'outbox',
            {
              'status': 'conflict',
              'error':
                  'Both this device and another device changed the planner.',
            },
            where: 'owner_uid = ?',
            whereArgs: [owner],
          );
        });
        notifyListeners();
      });
  Future<List<Json>> conflicts(String owner) async => (await database.query(
    'conflicts',
    where: 'owner_uid = ?',
    whereArgs: [owner],
    orderBy: 'created_at DESC',
  )).map((r) => Map<String, dynamic>.from(r)).toList();
  Future<void> resolveConflict(
    String owner,
    String id, {
    required bool useRemote,
  }) => exclusive(() async {
    final conflicts = await database.query(
      'conflicts',
      where: 'id = ? AND owner_uid = ?',
      whereArgs: [id, owner],
    );
    if (conflicts.isEmpty)
      throw const FormatException('Conflict copy no longer exists.');
    final conflict = conflicts.first;
    final next = useRemote
        ? parseBackup(conflict['remote_document'] as String)
        : clone(_state);
    await _commit(
      next,
      enqueue: !useRemote,
      remoteVersion: conflict['remote_version'] as int,
      clearOwner: owner,
    );
    // Keep both conflict documents as recoverable history after resolution.
    notifyListeners();
  });
  Future<void> recordFailure(
    String id,
    int attempts,
    String message, {
    required bool permanent,
  }) => exclusive(() async {
    final delay = 2000 * (1 << (attempts > 8 ? 8 : attempts));
    await database.update(
      'outbox',
      {
        'attempts': attempts,
        'next_attempt': DateTime.now().millisecondsSinceEpoch + delay,
        'error': message,
        'status': permanent ? 'failed' : 'pending',
      },
      where: 'operation_id = ?',
      whereArgs: [id],
    );
    notifyListeners();
  });
}
