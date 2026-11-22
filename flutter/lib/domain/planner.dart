import 'dart:convert';
import 'dart:math' as math;
import 'package:uuid/uuid.dart';

typedef Json = Map<String, dynamic>;
String newId() => const Uuid().v4();
String isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
double number(dynamic value) =>
    value is num && value.isFinite ? value.toDouble() : 0;
Json clone(Json value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
List<Json> rows(dynamic value) => (value is List ? value : const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

Json initialState() => clone({
  'version': 1,
  'currency': 'INR',
  'income': {
    'mode': 'net',
    'net': 0,
    'gross': 0,
    'deductions': [],
    'others': [],
    'freq': 'monthly',
    'nextPayDate': '',
    'configured': false,
  },
  'budget': {
    'incomeOverride': null,
    'categories': [
      for (final name in [
        'Rent',
        'Food',
        'Transport',
        'Bills',
        'Subscriptions',
        'Fun',
        'Savings',
      ])
        {
          'id': newId(),
          'name': name,
          'type': name == 'Savings'
              ? 'savings'
              : ['Fun', 'Subscriptions'].contains(name)
              ? 'wants'
              : 'needs',
          'planned': 0,
          'actual': 0,
        },
    ],
    'expenses': [],
  },
  'settings': {
    'dark': true,
    'cashOnHand': 0,
    'theme': 'lavender',
    'habits': [],
  },
  'student': {
    'allowance': 0,
    'arrivalDay': 1,
    'semester': {'start': '', 'end': '', 'heavyMonths': []},
  },
  'meta': {
    'startedAt': isoDate(DateTime.now()),
    'budgetMonth': isoDate(DateTime.now()).substring(0, 7),
  },
  'wallet': {
    'cash': [],
    'ious': [],
    'transport': [],
    'taxes': [],
    'deadlines': [],
  },
  'goals': [],
  'gifts': [],
  'debts': [],
  'subscriptions': [],
  'recurring': [],
  'yearlyBills': [],
  'incomeLog': [],
  'wishlist': [],
  'history': [],
  'rules': [],
  'payslips': [],
  'groups': [],
  'travelTrips': [],
  'groupData': {},
  'groupRecurring': [],
  'split': {'buckets': []},
  'debtSettings': {'extra': 0, 'strategy': 'avalanche'},
  'challenges': [],
});

/// Validates backups before writing; preserves fields belonging to the JS app.
Json parseBackup(String text) {
  if (text.length > 20 * 1024 * 1024)
    throw const FormatException('Backup exceeds 20 MB.');
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic> ||
      decoded['budget'] is! Map ||
      decoded['budget']['categories'] is! List ||
      decoded['budget']['expenses'] is! List) {
    throw const FormatException('Select a HEIST / Yoko JSON backup.');
  }
  if (decoded['version'] != null && decoded['version'] != 1) {
    throw const FormatException('This backup version is not supported.');
  }
  void validate(dynamic value, String key) {
    if (value is num &&
        (!value.isFinite ||
            ([
                  'amount',
                  'planned',
                  'target',
                  'saved',
                  'balance',
                  'rate',
                  'minPayment',
                ].contains(key) &&
                value < 0))) {
      throw FormatException('Invalid number in $key.');
    }
    if (value is Map) {
      for (final entry in value.entries) {
        validate(entry.value, entry.key.toString());
      }
    } else if (value is List) {
      for (final entry in value) {
        validate(entry, key);
      }
    }
  }

  validate(decoded, '');
  final base = initialState();
  final result = {...base, ...decoded};
  for (final key in [
    'budget',
    'settings',
    'income',
    'wallet',
    'meta',
    'student',
    'split',
    'debtSettings',
  ]) {
    if (decoded[key] != null && decoded[key] is! Map)
      throw FormatException('Invalid $key.');
    result[key] = {...(base[key] as Map), ...((decoded[key] ?? {}) as Map)};
  }
  for (final path in [
    'budget.categories',
    'budget.expenses',
    'goals',
    'debts',
    'wallet.ious',
    'wallet.cash',
    'subscriptions',
    'recurring',
    'yearlyBills',
    'incomeLog',
    'gifts',
    'wishlist',
    'wallet.transport',
    'wallet.taxes',
    'wallet.deadlines',
    'payslips',
    'travelTrips',
  ]) {
    final parts = path.split('.');
    final dynamic list = parts.length == 1
        ? result[path]
        : result[parts.first][parts.last];
    if (list is! List || list.any((x) => x is! Map<String, dynamic>))
      throw FormatException('Invalid $path.');
    final ids = <String>{};
    for (final item in list) {
      if (item['id'] is! String ||
          (item['id'] as String).isEmpty ||
          !ids.add(item['id'] as String))
        throw FormatException('Missing or duplicate ID in $path.');
    }
  }
  for (final expense in result['budget']['expenses'] as List) {
    if (expense['amount'] is! num ||
        expense['date'] is! String ||
        !validDate(expense['date']))
      throw const FormatException('Invalid expense amount or date.');
  }
  for (final trip in rows(result['travelTrips'])) {
    if (trip['destination'] is! String ||
        trip['startDate'] is! String ||
        !validDate(trip['startDate']) ||
        trip['days'] is! int ||
        trip['days'] < 1 ||
        trip['days'] > 14 ||
        trip['travelers'] is! int ||
        trip['travelers'] < 1 ||
        trip['travelers'] > 30 ||
        trip['budget'] is! num ||
        number(trip['budget']) <= 0 ||
        trip['currency'] is! String ||
        trip['people'] is! List ||
        (trip['people'] as List).any((p) => p is! String) ||
        (trip['people'] as List).length != trip['travelers'] ||
        trip['expenses'] is! List) {
      throw const FormatException(
        'Invalid travel trip. Existing data was preserved.',
      );
    }
    if (trip['plan'] != null &&
        (trip['plan'] is! Map ||
            trip['plan']['days'] is! List ||
            trip['plan']['budget'] is! List ||
            (trip['plan']['hotels'] != null &&
                trip['plan']['hotels'] is! List) ||
            (trip['plan']['warnings'] != null &&
                trip['plan']['warnings'] is! List))) {
      throw const FormatException('Invalid travel itinerary.');
    }
    for (final day in rows(trip['plan']?['days'])) {
      if (day['stops'] is! List)
        throw const FormatException('Invalid travel stops.');
    }
    if (trip['research'] != null &&
        (trip['research'] is! Map ||
            trip['research']['summary'] is! String ||
            trip['research']['sources'] is! List)) {
      throw const FormatException('Invalid travel research.');
    }
    for (final expense in rows(trip['expenses'])) {
      if (expense['amount'] is! num ||
          number(expense['amount']) <= 0 ||
          !(trip['people'] as List).contains(expense['paidBy'])) {
        throw const FormatException('Invalid trip expense.');
      }
    }
  }
  return result;
}

bool validDate(String text) {
  final d = DateTime.tryParse(text);
  return d != null && isoDate(d) == text;
}

class Planner {
  final Json state;
  final DateTime now;
  Planner(this.state, {DateTime? clock}) : now = clock ?? DateTime.now();
  String get today => isoDate(now);
  List<Json> get categories => rows(state['budget']['categories']);
  List<Json> get expenses => rows(state['budget']['expenses']);
  double frequency(dynamic freq) => switch (freq) {
    'weekly' => 52 / 12,
    'biweekly' => 26 / 12,
    'semimonthly' => 2,
    'yearly' => 1 / 12,
    _ => 1,
  };
  double get income {
    if (state['budget']['incomeOverride'] is num)
      return number(state['budget']['incomeOverride']);
    final i = state['income'] as Map;
    var net = number(i['net']);
    if (i['mode'] == 'gross') {
      final gross = number(i['gross']);
      net = math.max(
        0,
        gross -
            rows(i['deductions']).fold<double>(
              0,
              (v, d) =>
                  v +
                  (d['mode'] == 'percent'
                      ? gross * number(d['value']) / 100
                      : number(d['value'])),
            ),
      );
    }
    return net * frequency(i['freq']) +
        rows(i['others']).fold<double>(
          0,
          (v, x) => v + number(x['amount']) * frequency(x['freq']),
        );
  }

  DateTime anchorMonth(DateTime anchor, int offset) {
    final month = DateTime(anchor.year, anchor.month + offset, 1);
    return DateTime(
      month.year,
      month.month,
      math.min(anchor.day, DateTime(month.year, month.month + 1, 0).day),
    );
  }

  ({String start, String end, int days}) get period {
    final date = DateTime(now.year, now.month, now.day);
    final i = state['income'] as Map;
    final anchor = DateTime.tryParse(i['nextPayDate']?.toString() ?? '');
    if (income > 0 &&
        i['irregular'] != true &&
        i['freq'] == 'monthly' &&
        anchor != null) {
      final offset = (now.year - anchor.year) * 12 + now.month - anchor.month;
      var start = anchorMonth(anchor, offset);
      if (start.isAfter(date)) start = anchorMonth(anchor, offset - 1);
      final next = anchorMonth(
        anchor,
        (start.year - anchor.year) * 12 + start.month - anchor.month + 1,
      );
      return (
        start: isoDate(start),
        end: isoDate(next),
        days: math.max(1, next.difference(date).inDays),
      );
    }
    final end = DateTime(now.year, now.month + 1, 1);
    return (
      start: isoDate(DateTime(now.year, now.month, 1)),
      end: isoDate(end),
      days: math.max(1, end.difference(date).inDays),
    );
  }

  List<Json> get currentExpenses => expenses
      .where(
        (e) =>
            e['date'].compareTo(period.start) >= 0 &&
            e['date'].compareTo(today) <= 0,
      )
      .toList();
  double get spent =>
      currentExpenses.fold(0, (v, e) => v + number(e['amount']));
  double actual(String category) => currentExpenses
      .where((e) => e['categoryId'] == category)
      .fold(0, (v, e) => v + number(e['amount']));
  double get balance {
    final bank = state['settings']['bank'];
    if (bank is Map && bank['use'] == true) {
      return number(bank['amount']) -
          (expenses.fold<double>(0, (v, x) => v + number(x['amount'])) -
              number(bank['spentBase'])) +
          (rows(
                state['incomeLog'],
              ).fold<double>(0, (v, x) => v + number(x['amount'])) -
              number(bank['incomeBase']));
    }
    return (income > 0 ? income : number(state['settings']['cashOnHand'])) -
        spent;
  }

  List<({String date, Json item})> get dueBills {
    final output = <({String date, Json item})>[];
    for (final r in rows(
      state['recurring'],
    ).where((r) => r['active'] != false)) {
      final anchor = DateTime.tryParse(r['start']?.toString() ?? '');
      if (anchor == null) continue;
      // Iterate from the anchor without month-end drift. Bounded at 100 years.
      for (var n = 0; n < 36600; n++) {
        final d = switch (r['freq']) {
          'weekly' => anchor.add(Duration(days: n * 7)),
          'yearly' => anchorMonth(anchor, n * 12),
          _ => anchorMonth(anchor, n),
        };
        final date = isoDate(d);
        if (date.compareTo(period.end) >= 0) break;
        if (date.compareTo(today) > 0) output.add((date: date, item: r));
      }
    }
    for (final r in rows(state['yearlyBills'])) {
      final d = r['due']?.toString() ?? '';
      if (d.compareTo(today) > 0 && d.compareTo(period.end) < 0)
        output.add((date: d, item: r));
    }
    output.sort((a, b) => a.date.compareTo(b.date));
    return output;
  }

  double get reserved {
    final bills = dueBills.fold<double>(
      0,
      (v, r) => v + number(r.item['amount']),
    );
    return bills +
        rows(state['debts']).fold<double>(0, (v, d) {
          final paid = rows(d['payments'])
              .where(
                (p) =>
                    (p['date'] as String).compareTo(period.start) >= 0 &&
                    (p['date'] as String).compareTo(today) <= 0,
              )
              .fold<double>(0, (v, p) => v + number(p['amount']));
          return v +
              math.min(
                number(d['balance']),
                math.max(0, number(d['minPayment']) - paid),
              );
        });
  }

  double get spentToday => expenses
      .where((e) => e['date'] == today)
      .fold(0, (v, e) => v + number(e['amount']));
  double get dailyLimit =>
      math.max(0, balance + spentToday - reserved) / period.days;
  double get leftToday => math.max(0, dailyLimit - spentToday);
  String categoryName(dynamic id) =>
      categories.where((c) => c['id'] == id).firstOrNull?['name']?.toString() ??
      'Uncategorised';
}
