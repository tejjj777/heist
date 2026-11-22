import 'package:flutter_test/flutter_test.dart';
import 'package:heist_flutter/domain/finance.dart';
import 'package:heist_flutter/domain/imports.dart';

void main() {
  test('zero-interest amortization closes with exact cents', () {
    final schedule = amortization(1000, 0, 3);
    expect(schedule.last['balance'], 0);
    expect(
      schedule.map((r) => r['payment'] as double).reduce((a, b) => a + b),
      1000,
    );
  });
  test('non-amortizing debt never claims a payoff date', () {
    final result = simulatePayoff(
      [
        {'id': 'a', 'balance': 1000, 'rate': 24, 'minPayment': 10},
      ],
      0,
      'avalanche',
    );
    expect(result.paidOff, false);
  });
  test('extra payment pays debt faster', () {
    final debts = [
      {'id': 'a', 'balance': 10000, 'rate': 18, 'minPayment': 500},
    ];
    expect(
      simulatePayoff(debts, 500, 'avalanche').months.length,
      lessThan(simulatePayoff(debts, 0, 'avalanche').months.length),
    );
  });
  test('CSV import separates debit and credit and skips invalid rows', () {
    final rows = parseTransactions(
      'Date,Description,Debit,Credit\n21/11/2026,Food,120,\n22/11/2026,Allowance,,1000\nbad,broken,no,',
      today: '2026-11-22',
    );
    expect(rows, hasLength(2));
    expect(rows.first['amount'], 120);
    expect(rows.first['income'], false);
    expect(rows.last['income'], true);
    expect(rows.first['date'], '2026-11-21');
  });
}
