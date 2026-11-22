import 'package:flutter_test/flutter_test.dart';
import 'package:heist_flutter/domain/groups.dart';
import 'package:heist_flutter/domain/planner.dart';

void main() {
  test('group balances ignore crew records and settlement closes the debt', () {
    final cached = <String, dynamic>{
      'members': [
        {'id': 'a', 'name': 'A'},
        {'id': 'b', 'name': 'B'},
      ],
      'expenses': [
        {
          'id': 'one',
          'paid_by': 'a',
          'amount': 10.01,
          'description': 'Meal',
          'group_expense_splits': [
            {'member_id': 'a', 'amount': 5.01},
            {'member_id': 'b', 'amount': 5},
          ],
        },
        {
          'id': 'crew',
          'paid_by': 'a',
          'amount': 1000,
          'description': 'HEIST_DEPOSIT {}',
          'group_expense_splits': [],
        },
      ],
    };
    final transfer = groupTransfers(cached).single;
    expect(transfer['from'], 'b');
    expect(transfer['to'], 'a');
    expect(transfer['amountMinor'], 500);
    (cached['expenses'] as List).add({
      'id': 'settled',
      'paid_by': 'b',
      'amount': 5,
      'description': 'Settlement: B paid A',
      'group_expense_splits': [
        {'member_id': 'a', 'amount': 5},
      ],
    });
    expect(groupTransfers(cached), isEmpty);
  });
  test(
    'remote group spending imports only newly received shares and never duplicates',
    () {
      final s = initialState();
      s['groups'] = [
        {'id': 'g', 'name': 'Group', 'myMemberId': 'a'},
      ];
      s['groupData'] = clone({
        'g': {
          'expenses': [
            {'id': 'old', 'description': 'Old meal'},
          ],
        },
      });
      syncGroupBudget(s, 'g');
      expect(s['budget']['expenses'], isEmpty);
      s['groupData']['g']['expenses'].add({
        'id': 'new',
        'description': 'New meal',
        'created_at': '2026-11-22T12:00:00Z',
        'group_expense_splits': [
          {'member_id': 'a', 'amount': 12.34},
        ],
      });
      syncGroupBudget(s, 'g');
      syncGroupBudget(s, 'g');
      expect(s['budget']['expenses'].length, 1);
      expect(s['budget']['expenses'][0]['amount'], 12.34);
    },
  );
}
