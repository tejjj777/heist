import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../domain/planner.dart';
import '../domain/groups.dart';
import 'backend.dart';
import 'local_store.dart';
import 'sync_engine.dart' show sameDocument;

/// Keeps the legacy anonymous group identity separate from the email vault user.
class GroupService extends ChangeNotifier {
  final LocalStore store;
  final HeistBackend backend;
  bool busy = false, online = true;
  String? error;
  Timer? _timer;
  GroupService(this.store, this.backend);
  Future<void> start() async {
    await backend.initialize();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => synchronize());
  }

  Future<void> authenticate() async {
    if (backend.session != null) {
      await backend.accessToken();
      return;
    }
    final value = await backend.request(
      '/auth/v1/signup',
      method: 'POST',
      auth: false,
      body: {'data': {}},
    );
    await backend.setSession(Map<String, dynamic>.from(value as Map));
  }

  Future<void> create(String name, String memberName) async {
    if (!online)
      throw BackendFailure(
        0,
        'Creating or joining a live group needs internet. Existing group expenses can be added offline.',
      );
    await authenticate();
    final id = newId();
    final joinCode = newId().replaceAll('-', '').substring(0, 6).toUpperCase();
    final group = rows(
      await backend.request(
        '/rest/v1/groups',
        method: 'POST',
        prefer: 'return=representation',
        body: {'id': id, 'name': name, 'join_code': joinCode},
      ),
    ).single;
    final member = rows(
      await backend.request(
        '/rest/v1/group_members',
        method: 'POST',
        prefer: 'return=representation',
        body: {'group_id': id, 'user_id': backend.uid, 'name': memberName},
      ),
    ).single;
    await store.put('groups', {
      'id': group['id'],
      'name': group['name'],
      'joinCode': group['join_code'],
      'myMemberId': member['id'],
    });
    await refresh(id);
  }

  Future<void> join(String code, String memberName) async {
    if (!online) throw BackendFailure(0, 'Joining a group needs internet.');
    await authenticate();
    final id = await backend.request(
      '/rest/v1/rpc/join_group',
      method: 'POST',
      body: {'code': code.toUpperCase(), 'member_name': memberName},
    );
    final group = rows(
      await backend.request(
        '/rest/v1/groups?id=eq.${Uri.encodeComponent(id.toString())}&select=*',
      ),
    ).single;
    final member = rows(
      await backend.request(
        '/rest/v1/group_members?group_id=eq.${Uri.encodeComponent(id.toString())}&user_id=eq.${backend.uid}&select=*',
      ),
    ).single;
    await store.put('groups', {
      'id': group['id'],
      'name': group['name'],
      'joinCode': group['join_code'],
      'myMemberId': member['id'],
    });
    await refresh(id.toString());
  }

  Future<void> addExpense(
    Json group,
    String description,
    double amount,
    Map<String, int> shares,
    String categoryId,
  ) async {
    final uid = backend.uid;
    if (uid == null)
      throw BackendFailure(
        401,
        'Join this group on this device before adding offline expenses.',
      );
    final cached = (store.state['groupData'] as Map?)?[group['id']] as Map?;
    final members = rows(cached?['members']);
    if (!members.any(
      (m) => m['id'] == group['myMemberId'] && m['user_id'] == uid,
    ))
      throw BackendFailure(
        403,
        'Rejoin the group to establish this device’s member identity.',
      );
    final cents = (amount * 100).round();
    if (cents <= 0 ||
        shares.values.fold<int>(0, (v, n) => v + n) != cents ||
        shares.values.any((n) => n < 0) ||
        shares.keys.any((id) => !members.any((m) => m['id'] == id)))
      throw const FormatException('Shares must add up to the expense amount.');
    final expense = {
      'id': newId(),
      'group_id': group['id'],
      'paid_by': group['myMemberId'],
      'description': description,
      'amount': cents / 100,
    };
    final splits = [
      for (final entry in shares.entries)
        {
          'id': newId(),
          'expense_id': expense['id'],
          'member_id': entry.key,
          'amount': entry.value / 100,
        },
    ];
    await store.groupMutation(
      uid,
      {
        'operation_id': newId(),
        'type': 'ADD_EXPENSE',
        'expense': expense,
        'splits': splits,
      },
      (state) {
        state['groupData'] ??= <String, dynamic>{};
        state['groupData'][group['id']] ??= {
          'members': members,
          'expenses': [],
        };
        (state['groupData'][group['id']]['expenses'] as List).add({
          ...expense,
          'group_expense_splits': splits,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        final mine = shares[group['myMemberId']] ?? 0;
        if (mine > 0 &&
            !description.startsWith('Settlement:') &&
            !description.startsWith('HEIST_GOAL ') &&
            !description.startsWith('HEIST_DEPOSIT '))
          (state['budget']['expenses'] as List).add({
            'id': newId(),
            'date': isoDate(DateTime.now()),
            'categoryId': categoryId,
            'amount': mine / 100,
            'note': '${group['name']}: $description',
            'groupExp': expense['id'],
          });
      },
    );
    unawaited(synchronize());
  }

  Future<void> refresh(String id) async {
    final members = rows(
      await backend.request(
        '/rest/v1/group_members?group_id=eq.${Uri.encodeComponent(id)}&select=*',
      ),
    );
    final expenses = rows(
      await backend.request(
        '/rest/v1/group_expenses?group_id=eq.${Uri.encodeComponent(id)}&select=*,group_expense_splits(*)',
      ),
    );
    final pendingIds = backend.uid == null
        ? <String>{}
        : (await store.pending(backend.uid!))
              .where((o) => o['kind'] == 'group')
              .map(
                (o) =>
                    (jsonDecode(o['document']) as Map)['expense']['id']
                        as String,
              )
              .toSet();
    final previous = (store.state['groupData'] as Map?)?[id];
    final oldExpenses = rows(previous is Map ? previous['expenses'] : null);
    final mergedExpenses = [
      ...expenses,
      ...oldExpenses.where(
        (e) =>
            pendingIds.contains(e['id']) &&
            !expenses.any((r) => r['id'] == e['id']),
      ),
    ];
    final nextGroup = <String, dynamic>{
      'members': members,
      'expenses': mergedExpenses,
    };
    if (previous is Map &&
        (store.state['meta']['groupSeen'] as Map?)?[id] == true &&
        sameDocument(Map<String, dynamic>.from(previous), nextGroup))
      return;
    await store.mutate((state) {
      state['groupData'] ??= <String, dynamic>{};
      state['groupData'][id] = nextGroup;
      syncGroupBudget(state, id);
    });
  }

  Future<void> synchronize() async {
    if (busy || !online || backend.uid == null) return;
    if (await store.synchronizationPaused()) return;
    if (busy) return;
    busy = true;
    var failed = false;
    notifyListeners();
    try {
      final queue = (await store.pending(
        backend.uid!,
      )).where((r) => r['kind'] == 'group').toList().reversed;
      for (final row in queue) {
        if (row['status'] != 'pending' ||
            number(row['next_attempt']) > DateTime.now().millisecondsSinceEpoch)
          continue;
        try {
          final operation = jsonDecode(row['document'] as String) as Map;
          final expense = Map<String, dynamic>.from(operation['expense']);
          await _insertOnce('group_expenses', expense);
          for (final split in rows(operation['splits'])) {
            await _insertOnce('group_expense_splits', split);
          }
          await store.acknowledgeGroup(row['operation_id']);
        } catch (failure) {
          failed = true;
          error = failure.toString();
          await store.recordFailure(
            row['operation_id'],
            (row['attempts'] as int) + 1,
            error!,
            permanent: failure is BackendFailure && !failure.retryable,
          );
          break;
        }
      }
      for (final group in rows(store.state['groups'])) {
        await refresh(group['id']);
      }
      if (!failed) error = null;
    } catch (failure) {
      error = failure.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _insertOnce(String table, Json record) async {
    try {
      await backend.request('/rest/v1/$table', method: 'POST', body: record);
    } on BackendFailure catch (failure) {
      if (failure.status != 409) rethrow;
      final existing = rows(
        await backend.request('/rest/v1/$table?id=eq.${record['id']}&select=*'),
      ).firstOrNull;
      if (existing == null ||
          !sameDocument(record, {for (final k in record.keys) k: existing[k]}))
        throw BackendFailure(
          409,
          'Conflicting group record. No remote data was overwritten.',
        );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
