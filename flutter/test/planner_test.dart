import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:heist_flutter/domain/planner.dart';

void main() {
  test('legacy backup preserves unknown and live group data', () {
    final state = initialState();
    state['groupData'] = {
      'trip': {
        'unfamiliar': [1, 2, 3],
      },
    };
    state['futureField'] = {'keep': true};
    expect(parseBackup(jsonEncode(state)), state);
  });
  test('reject unrelated JSON, duplicate IDs and invalid dates', () {
    expect(() => parseBackup('{}'), throwsFormatException);
    final state = initialState();
    state['budget']['expenses'] = [
      {'id': 'x', 'date': '2026-02-30', 'amount': 40},
    ];
    expect(() => parseBackup(jsonEncode(state)), throwsFormatException);
    state['budget']['expenses'] = [
      {'id': 'x', 'date': '2026-11-21', 'amount': 40},
      {'id': 'x', 'date': '2026-11-21', 'amount': 50},
    ];
    expect(() => parseBackup(jsonEncode(state)), throwsFormatException);
  });
  test(
    'today spending reduces today allowance once, never changes day opening limit',
    () {
      final state = initialState();
      state['budget']['incomeOverride'] = 3000;
      state['budget']['expenses'] = [
        {'id': 'x', 'categoryId': 'food', 'amount': 100, 'date': '2026-11-21'},
      ];
      final planner = Planner(state, clock: DateTime(2026, 11, 21));
      expect(planner.period.days, 10);
      expect(planner.balance, 2900);
      expect(planner.dailyLimit, 300);
      expect(planner.leftToday, 200);
    },
  );
  test('month end payday stays anchored after February', () {
    final state = initialState();
    state['budget']['incomeOverride'] = 3000;
    state['income']['nextPayDate'] = '2026-01-31';
    final february = Planner(state, clock: DateTime(2026, 2, 28));
    expect(february.period.start, '2026-02-28');
    expect(february.period.end, '2026-03-31');
  });
  test('future expenses excluded and debt payments reduce reserve', () {
    final state = initialState();
    state['budget']['incomeOverride'] = 3000;
    state['budget']['expenses'] = [
      {'id': 'future', 'amount': 1000, 'date': '2026-12-01'},
    ];
    state['debts'] = [
      {
        'id': 'debt',
        'balance': 800,
        'minPayment': 100,
        'payments': [
          {'id': 'paid', 'date': '2026-11-20', 'amount': 40},
        ],
      },
    ];
    final p = Planner(state, clock: DateTime(2026, 11, 21));
    expect(p.spent, 0);
    expect(p.reserved, 60);
  });
  test('a negative expense backup is rejected', () {
    final state = initialState();
    state['budget']['expenses'] = [
      {'id': 'bad', 'date': '2026-11-21', 'amount': -20},
    ];
    expect(() => parseBackup(jsonEncode(state)), throwsFormatException);
  });
}
