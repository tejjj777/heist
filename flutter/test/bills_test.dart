import 'package:flutter_test/flutter_test.dart';
import 'package:heist_flutter/domain/bills.dart';

void main() {
  test('assigned item shares and proportional charges preserve every cent', () {
    final result = itemizedShares(
      ['You', 'A', 'B'],
      'Pizza | 100.01 | You, A, B\nTea | 10 | A',
      charges: 123,
    );
    expect(result.values.fold<int>(0, (a, b) => a + b), 11124);
    expect(result['A']! > result['You']!, true);
  });
  test('unknown item assignees are rejected before any write', () {
    expect(
      () => itemizedShares(['You', 'A'], 'Tea | 10 | Unknown'),
      throwsFormatException,
    );
  });
}
