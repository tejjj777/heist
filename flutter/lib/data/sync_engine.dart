import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../domain/planner.dart';
import 'backend.dart';
import 'local_store.dart';
import 'vault_crypto.dart';

/// Durable snapshot queue matches the existing encrypted-vault API. CAS prevents
/// duplicate uploads and a conflict is never silently resolved by wall-clock time.
class SyncEngine extends ChangeNotifier {
  final LocalStore store;
  final HeistBackend backend;
  final VaultCrypto crypto;
  bool online = true, busy = false;
  bool _disposed = false;
  bool _selectingAccount = false;
  int pending = 0;
  String? error;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  SyncEngine(this.store, this.backend, {VaultCrypto? crypto})
    : crypto = crypto ?? VaultCrypto();
  bool get ready =>
      backend.uid != null && backend.dataKey != null && !_selectingAccount;
  Future<void> selectAccount(Future<void> Function() action) async {
    if (busy || _selectingAccount)
      throw const FormatException(
        'Wait for synchronization to finish, then unlock again.',
      );
    _selectingAccount = true;
    notifyListeners();
    try {
      final owner = await store.accountOwner();
      if (owner != null && owner != backend.uid)
        throw const FormatException(
          'Sign out before selecting a different account.',
        );
      await action();
    } finally {
      _selectingAccount = false;
      if (!_disposed) {
        notifyListeners();
        schedule();
      }
    }
  }

  Future<void> start({
    bool watchConnectivity = true,
    bool poll = true,
    Uri? incomingLink,
  }) async {
    await backend.initialize();
    if (incomingLink != null) await backend.acceptAuthLink(incomingLink);
    pending = await store.pendingCount();
    if (watchConnectivity) {
      final results = await Connectivity().checkConnectivity();
      online = !results.contains(ConnectivityResult.none);
      _connectivity = Connectivity().onConnectivityChanged.listen((values) {
        online = !values.contains(ConnectivityResult.none);
        notifyListeners();
        if (online) schedule();
      });
    }
    store.addListener(schedule);
    if (poll)
      _timer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => synchronize(),
      );
    schedule();
  }

  void schedule() {
    unawaited(_refreshCount());
    if (!busy && online && ready) unawaited(synchronize());
  }

  Future<void> _refreshCount() async {
    pending = await store.pendingCount();
    if (!_disposed) notifyListeners();
  }

  Future<void> synchronize({bool manual = false}) async {
    if (busy || !online || !ready) return;
    if (await store.accountOwner() != backend.uid) {
      error = 'Choose your planner before synchronizing this account.';
      if (!_disposed) notifyListeners();
      return;
    }
    if (await store.synchronizationPaused()) {
      error =
          'Synchronization paused after restore. Review your data, then resume.';
      notifyListeners();
      return;
    }
    if (busy || _disposed || !ready) return;
    busy = true;
    notifyListeners();
    Json? operation;
    try {
      final uid = backend.uid!;
      final queued = (await store.pending(
        uid,
      )).where((row) => row['kind'] == 'vault').toList();
      operation = queued.firstOrNull;
      if (operation != null) {
        if (operation['status'] == 'conflict') {
          error = 'Resolve the saved conflict before syncing.';
          return;
        }
        if (!manual &&
            (operation['status'] == 'failed' ||
                number(operation['next_attempt']) >
                    DateTime.now().millisecondsSinceEpoch))
          return;
      }
      final row = await backend.vault();
      if (row == null)
        throw BackendFailure(
          404,
          'Account vault not found. Local data and pending changes are preserved.',
        );
      final remote = await crypto.unlock(
        row['data'] as String,
        backend.dataKey!,
      );
      final version = (row['version'] as num).toInt();
      if (operation == null) {
        if (version != await store.remoteVersion())
          await store.acceptRemoteIfClean(uid, remote, version);
      } else {
        final local = parseBackup(operation['document'] as String);
        if (sameDocument(local, remote)) {
          // The previous PATCH may have committed even when its response was lost.
          await store.acknowledge(uid, operation['revision'] as int, version);
        } else if (version != operation['base_version']) {
          await store.parkConflict(uid, remote, version);
          error =
              'Both devices changed the planner. Both copies were saved. Choose which to keep.';
          return;
        } else {
          final updated = await backend.compareAndSwap(
            version,
            await crypto.lock(local, backend.dataKey!),
          );
          if (updated == null) {
            // CAS lost a race. Pull on the next pass; do not retry blindly.
            error =
                'Another device saved first. Checking for a conflict on the next attempt.';
            return;
          }
          await store.acknowledge(
            uid,
            operation['revision'] as int,
            (updated['version'] as num).toInt(),
          );
        }
      }
      error = null;
    } catch (failure) {
      error = failure is BackendFailure
          ? failure.message
          : 'Could not unlock or synchronize the vault. Local data was preserved.';
      if (operation != null)
        await store.recordFailure(
          operation['operation_id'] as String,
          (operation['attempts'] as int) + 1,
          error!,
          permanent: failure is BackendFailure && !failure.retryable,
        );
    } finally {
      busy = false;
      await _refreshCount();
    }
  }

  Future<void> resolve(String id, {required bool useRemote}) async {
    if (backend.uid == null) return;
    await store.resolveConflict(backend.uid!, id, useRemote: useRemote);
    error = null;
    await synchronize(manual: true);
  }

  @override
  void dispose() {
    _disposed = true;
    store.removeListener(schedule);
    _timer?.cancel();
    _connectivity?.cancel();
    super.dispose();
  }
}

dynamic canonical(dynamic value) {
  if (value is num && value.isFinite && value == value.roundToDouble())
    return value.toInt();
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonical(value[key])};
  }
  if (value is List) return value.map(canonical).toList();
  return value;
}

bool sameDocument(Json a, Json b) =>
    jsonEncode(canonical(a)) == jsonEncode(canonical(b));
