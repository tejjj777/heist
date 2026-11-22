import 'dart:math' as math;
import 'planner.dart';

bool isCrewRecord(Json expense) => RegExp(
  r'^HEIST_(GOAL|DEPOSIT) ',
).hasMatch(expense['description']?.toString() ?? '');
List<Json> groupBalances(Json cached) {
  final balances = {
    for (final m in rows(cached['members'])) m['id']: {...m, 'netMinor': 0},
  };
  for (final expense in rows(cached['expenses'])) {
    if (isCrewRecord(expense) || !balances.containsKey(expense['paid_by']))
      continue;
    balances[expense['paid_by']]!['netMinor'] =
        (balances[expense['paid_by']]!['netMinor'] as int) +
        (number(expense['amount']) * 100).round();
    for (final split in rows(expense['group_expense_splits'])) {
      final member = balances[split['member_id']];
      if (member != null)
        member['netMinor'] =
            (member['netMinor'] as int) -
            (number(split['amount']) * 100).round();
    }
  }
  return balances.values.toList();
}

List<Json> groupTransfers(Json cached) {
  final b = groupBalances(cached),
      debtors = b.where((m) => (m['netMinor'] as int) < 0).toList(),
      creditors = b.where((m) => (m['netMinor'] as int) > 0).toList();
  debtors.sort((a, b) => (a['netMinor'] as int).compareTo(b['netMinor']));
  creditors.sort((a, b) => (b['netMinor'] as int).compareTo(a['netMinor']));
  final result = <Json>[];
  var i = 0, j = 0;
  while (i < debtors.length && j < creditors.length) {
    final d = debtors[i],
        c = creditors[j],
        amount = math.min(-(d['netMinor'] as int), c['netMinor'] as int);
    result.add({
      'from': d['id'],
      'to': c['id'],
      'fromName': d['name'],
      'toName': c['name'],
      'amountMinor': amount,
    });
    d['netMinor'] = (d['netMinor'] as int) + amount;
    c['netMinor'] = (c['netMinor'] as int) - amount;
    if (d['netMinor'] == 0) i++;
    if (c['netMinor'] == 0) j++;
  }
  return result;
}

void syncGroupBudget(Json state, String groupId) {
  final group = rows(
    state['groups'],
  ).where((g) => g['id'] == groupId).firstOrNull;
  final cached = (state['groupData'] as Map?)?[groupId];
  final categories = rows(state['budget']['categories']);
  if (group == null || cached is! Map || categories.isEmpty) return;
  final meta = state['meta'] as Map;
  meta['groupSeen'] ??= <String, dynamic>{};
  meta['groupSkip'] ??= [];
  final skip = meta['groupSkip'] as List, expenses = rows(cached['expenses']);
  if (meta['groupSeen'][groupId] != true) {
    skip.addAll(expenses.map((e) => e['id']).where((id) => !skip.contains(id)));
    meta['groupSeen'][groupId] = true;
    return;
  }
  final personal = state['budget']['expenses'] as List;
  final category =
      categories
          .where((c) => c['id'] == state['settings']['groupCat'])
          .firstOrNull ??
      categories
          .where(
            (c) => RegExp(
              'outing|fun|food|canteen|snack|daily',
              caseSensitive: false,
            ).hasMatch(c['name'].toString()),
          )
          .firstOrNull ??
      categories.first;
  for (final expense in expenses) {
    if (skip.contains(expense['id']) ||
        personal.any((e) => e['groupExp'] == expense['id']) ||
        isCrewRecord(expense) ||
        expense['description'].toString().startsWith('Settlement:'))
      continue;
    final mine = rows(expense['group_expense_splits'])
        .where((s) => s['member_id'] == group['myMemberId'])
        .fold<double>(0, (v, s) => v + number(s['amount']));
    skip.add(expense['id']);
    if (mine <= 0.004) continue;
    final raw = expense['created_at']?.toString() ?? '',
        date = raw.length >= 10 ? raw.substring(0, 10) : '';
    personal.add({
      'id': newId(),
      'date': validDate(date) ? date : isoDate(DateTime.now()),
      'amount': (mine * 100).round() / 100,
      'categoryId': category['id'],
      'note': '${group['name']}: ${expense['description']}',
      'groupExp': expense['id'],
    });
  }
}
