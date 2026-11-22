import 'package:csv/csv.dart';
import 'planner.dart';

String? importDate(String text, {bool monthFirst = false}) {
  final iso = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(text)?.group(0);
  if (iso != null && validDate(iso)) return iso;
  final match = RegExp(
    r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b',
  ).firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match[3]!);
  final first = int.parse(match[1]!), second = int.parse(match[2]!);
  final fullYear = year < 100 ? 2000 + year : year;
  final month = monthFirst ? first : second, day = monthFirst ? second : first;
  final date = DateTime(fullYear, month, day);
  if (date.year != fullYear || date.month != month || date.day != day)
    return null;
  return isoDate(date);
}

double? parseAmount(String text) =>
    double.tryParse(text.replaceAll(RegExp(r'[^\d.\-]'), ''));
List<Json> parseTransactions(
  String text, {
  required String today,
  bool monthFirst = false,
}) {
  final normalized = text.replaceAll('\r\n', '\n').trim();
  if (normalized.isEmpty) return [];
  final table = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(normalized);
  final headers = table.isEmpty
      ? <String>[]
      : table.first.map((s) => s.toString().trim().toLowerCase()).toList();
  int index(List<String> names) => headers.indexWhere(
    (h) => names.any((name) => h == name || h.startsWith('$name ')),
  );
  final dateIndex = index([
    'date',
    'transaction date',
    'txn date',
    'value date',
  ]);
  final amountIndex = index(['amount', 'transaction amount']);
  final debitIndex = index(['debit', 'withdrawal', 'withdrawals']);
  final creditIndex = index(['credit', 'deposit', 'deposits']);
  final noteIndex = index([
    'description',
    'note',
    'narration',
    'merchant',
    'particulars',
    'details',
  ]);
  if (table.length > 1 &&
      dateIndex >= 0 &&
      (amountIndex >= 0 || debitIndex >= 0 || creditIndex >= 0)) {
    String cell(List<dynamic> row, int i) =>
        i >= 0 && i < row.length ? row[i].toString().trim() : '';
    return [
      for (final row in table.skip(1))
        (() {
          var amount = parseAmount(cell(row, amountIndex));
          var income = false;
          if (amountIndex < 0) {
            final debit = parseAmount(cell(row, debitIndex)) ?? 0,
                credit = parseAmount(cell(row, creditIndex)) ?? 0;
            if (debit > 0) {
              amount = debit;
            } else {
              amount = credit;
              income = true;
            }
          } else {
            final typeIndex = index(['type', 'direction', 'dr/cr']);
            income = RegExp(
              r'credit|income|^cr$',
              caseSensitive: false,
            ).hasMatch(cell(row, typeIndex));
            amount = amount?.abs();
          }
          final date = importDate(cell(row, dateIndex), monthFirst: monthFirst);
          if (amount == null || !amount.isFinite || amount <= 0 || date == null)
            return null;
          return <String, dynamic>{
            'id': newId(),
            'date': date,
            'amount': amount,
            'note': cell(row, noteIndex),
            'income': income,
          };
        })(),
    ].whereType<Json>().toList();
  }
  return [
    for (final line in normalized.split('\n'))
      (() {
        final match = RegExp(
          r'(?:Rs\.?|INR|₹|USD|\$)\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false,
        ).firstMatch(line);
        final amount = match == null ? null : parseAmount(match[1]!);
        if (amount == null || amount <= 0 || !amount.isFinite) return null;
        return <String, dynamic>{
          'id': newId(),
          'date': importDate(line, monthFirst: monthFirst) ?? today,
          'amount': amount,
          'note': line.substring(0, line.length > 120 ? 120 : line.length),
          'income': RegExp(
            r'credited|received|refund',
            caseSensitive: false,
          ).hasMatch(line),
        };
      })(),
  ].whereType<Json>().toList();
}

String transactionFingerprint(Json row) =>
    '${row['date']}|${(number(row['amount']) * 100).round()}|${row['note']?.toString().trim().toLowerCase()}';
