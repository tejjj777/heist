import 'package:flutter_test/flutter_test.dart';
import 'package:heist_flutter/domain/planner.dart';
import 'package:heist_flutter/domain/scheduled.dart';

void main() {
  test('monthly bills retain their anchor across short months', () {
    expect(
      recurringDates({
        'start': '2026-01-31',
        'freq': 'monthly',
      }, DateTime(2026, 3, 31)),
      ['2026-01-31', '2026-02-28', '2026-03-31'],
    );
  });
  test('overdue recurring posts once with linked debt principal', () {
    final s = initialState();
    s['meta']['budgetMonth'] = '2026-02';
    s['debts'] = [
      {'id': 'debt', 'balance': 1000, 'rate': 12, 'payments': []},
    ];
    s['recurring'] = [
      {
        'id': 'bill',
        'name': 'Loan',
        'amount': 100,
        'categoryId': s['budget']['categories'][0]['id'],
        'debtId': 'debt',
        'freq': 'monthly',
        'start': '2026-01-31',
        'lastPosted': '',
        'active': true,
      },
    ];
    applyScheduledChanges(s, DateTime(2026, 2, 28));
    expect(s['budget']['expenses'].length, 2);
    expect(s['debts'][0]['balance'], 819.10);
    expect(applyScheduledChanges(s, DateTime(2026, 2, 28)), false);
    expect(s['budget']['expenses'].length, 2);
  });
  test(
    'month rollover archives actuals, carries unused plan and is idempotent',
    () {
      final s = initialState();
      s['meta']['budgetMonth'] = '2026-01';
      final c = s['budget']['categories'][0];
      c['planned'] = 500;
      c['carry'] = true;
      s['budget']['expenses'] = [
        {'id': 'x', 'date': '2026-01-20', 'categoryId': c['id'], 'amount': 123},
      ];
      expect(applyScheduledChanges(s, DateTime(2026, 2, 1)), true);
      expect(s['history'][0]['cats'][0]['actual'], 123);
      expect(c['carryIn'], 377);
      expect(applyScheduledChanges(s, DateTime(2026, 2, 1)), false);
      expect(s['history'].length, 1);
    },
  );
}
