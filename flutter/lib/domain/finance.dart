import 'dart:math' as math;
import 'planner.dart';

class PayoffResult {
  final List<Json> months;
  final bool paidOff;
  final int interestMinor;
  PayoffResult(this.months, this.paidOff, this.interestMinor);
}

PayoffResult simulatePayoff(List<Json> debts, double extra, String strategy) {
  final balances = {
    for (final d in debts)
      d['id'] as String: (number(d['balance']) * 100).round(),
  };
  final budget =
      (debts.fold<double>(0, (s, d) => s + number(d['minPayment'])) * 100 +
              extra * 100)
          .round();
  final result = <Json>[];
  var totalInterest = 0;
  for (
    var month = 1;
    month <= 600 && balances.values.any((v) => v > 0);
    month++
  ) {
    final initial = balances.values.fold<int>(0, (a, b) => a + b);
    var interest = 0, left = budget;
    for (final d in debts) {
      final id = d['id'] as String;
      final charge = (balances[id]! * number(d['rate']) / 1200).round();
      balances[id] = balances[id]! + charge;
      interest += charge;
      final minimum = math.min(
        balances[id]!,
        (number(d['minPayment']) * 100).round(),
      );
      final paid = math.min(math.max(0, left), minimum);
      balances[id] = balances[id]! - paid;
      left -= paid;
    }
    final ordered = [...debts]
      ..sort(
        (a, b) => strategy == 'snowball'
            ? balances[a['id']]!.compareTo(balances[b['id']]!)
            : number(b['rate']).compareTo(number(a['rate'])),
      );
    for (final d in ordered) {
      final id = d['id'] as String;
      final paid = math.min(math.max(0, left), balances[id]!);
      balances[id] = balances[id]! - paid;
      left -= paid;
    }
    final remaining = balances.values.fold<int>(0, (a, b) => a + b);
    totalInterest += interest;
    result.add({
      'month': month,
      'payment': (budget - left) / 100,
      'interest': interest / 100,
      'balance': remaining / 100,
      'balances': {...balances},
    });
    if (remaining >= initial && budget <= interest) break;
  }
  return PayoffResult(
    result,
    balances.values.every((v) => v == 0),
    totalInterest,
  );
}

List<Json> amortization(double principal, double annualRate, int months) {
  if (!principal.isFinite ||
      principal < 0 ||
      !annualRate.isFinite ||
      annualRate < 0 ||
      months < 1 ||
      months > 600)
    throw const FormatException('Invalid loan inputs.');
  final rate = annualRate / 1200;
  final payment = rate == 0
      ? principal / months
      : principal * rate / (1 - math.pow(1 + rate, -months));
  var balance = (principal * 100).round();
  return [
    for (var month = 1; month <= months; month++)
      (() {
        final interest = (balance * rate).round();
        final paid = month == months
            ? balance + interest
            : math.min((payment * 100).round(), balance + interest);
        final principalPaid = paid - interest;
        balance -= principalPaid;
        return <String, dynamic>{
          'month': month,
          'payment': paid / 100,
          'principal': principalPaid / 100,
          'interest': interest / 100,
          'balance': balance / 100,
        };
      })(),
  ];
}
