import 'dart:math' as math;
import 'planner.dart';

/// Original recurringDue semantics: anchored month/year dates, 24 posts per run.
List<String> recurringDates(Json item, DateTime now) {
  final start = DateTime.tryParse(item['start']?.toString() ?? '');
  final after = item['lastPosted']?.toString() ?? '';
  if (start == null || !validDate(isoDate(start))) return [];
  final result = <String>[];
  for (var k = 0; k < 2000 && result.length < 24; k++) {
    DateTime date;
    if (item['freq'] == 'weekly') {
      date = DateTime(start.year, start.month, start.day + 7 * k);
    } else {
      final base = item['freq'] == 'yearly'
          ? DateTime(start.year + k, start.month, 1)
          : DateTime(start.year, start.month + k, 1);
      date = DateTime(
        base.year,
        base.month,
        math.min(start.day, DateTime(base.year, base.month + 1, 0).day),
      );
    }
    final iso = isoDate(date);
    if (iso.compareTo(isoDate(now)) > 0) break;
    if (after.isEmpty || iso.compareTo(after) > 0) result.add(iso);
  }
  return result;
}

/// Called inside the same serialized local transaction as other state changes.
bool applyScheduledChanges(Json state, DateTime now) {
  var changed = false;
  final expenses = state['budget']['expenses'] as List;
  final categories = state['budget']['categories'] as List;
  for (final dynamic record in state['recurring'] as List) {
    final r = Map<String, dynamic>.from(record as Map);
    if (r['active'] == false ||
        number(r['amount']) <= 0 ||
        !categories.any((c) => c['id'] == r['categoryId']))
      continue;
    for (final date in recurringDates(r, now)) {
      if (!expenses.any(
        (e) => e['recurringId'] == r['id'] && e['date'] == date,
      )) {
        final expense = <String, dynamic>{
          'id': newId(),
          'date': date,
          'categoryId': r['categoryId'],
          'amount': r['amount'],
          'note': 'Recurring: ${r['name']}',
          'recurringId': r['id'],
        };
        final debt = (state['debts'] as List)
            .where((d) => d['id'] == r['debtId'])
            .firstOrNull;
        if (debt != null && number(debt['balance']) > 0) {
          final rate =
              number(debt['rate']) /
              1200 *
              (r['freq'] == 'weekly'
                  ? 12 / 52
                  : r['freq'] == 'yearly'
                  ? 12
                  : 1);
          final principal =
              (math.max(
                        0,
                        math.min(
                          number(debt['balance']),
                          number(r['amount']) - number(debt['balance']) * rate,
                        ),
                      ) *
                      100)
                  .round() /
              100;
          if (principal > 0) {
            final id = newId();
            debt['payments'] ??= [];
            (debt['payments'] as List).add({
              'id': id,
              'date': date,
              'amount': principal,
            });
            debt['balance'] =
                (number(debt['balance']) * 100 - principal * 100).round() / 100;
            if (number(debt['balance']) <= 0.005) {
              debt['balance'] = 0;
              debt['defeatedAt'] = date;
            }
            expense['debtPay'] = {
              'debtId': debt['id'],
              'pid': id,
              'amount': principal,
            };
          }
        }
        expenses.add(expense);
      }
      record['lastPosted'] = date;
      changed = true;
    }
  }
  final meta = state['meta'] as Map;
  final month = isoDate(now).substring(0, 7),
      old = meta['budgetMonth']?.toString() ?? '';
  if (old.length == 7 && old.compareTo(month) < 0) {
    var date = DateTime.tryParse('$old-01');
    if (date != null) {
      final history = rows(state['history']);
      var from = (meta['periodStart']?.toString() ?? '').isNotEmpty
          ? meta['periodStart'].toString()
          : '$old-01';
      for (
        var k = 0;
        date != null &&
            isoDate(date).substring(0, 7).compareTo(month) < 0 &&
            k < 36;
        k++
      ) {
        final ym = isoDate(date).substring(0, 7),
            end = isoDate(DateTime(date.year, date.month + 1, 0));
        if (!(ym == old && meta['closedEarly'] == old)) {
          final spent = <String, double>{};
          for (final e in expenses) {
            if ((e['date'] as String).compareTo(from) >= 0 &&
                (e['date'] as String).compareTo(end) <= 0)
              spent[e['categoryId']] =
                  (spent[e['categoryId']] ?? 0) + number(e['amount']);
          }
          if (categories.any(
            (c) => (spent[c['id']] ?? 0) > 0 || number(c['planned']) > 0,
          )) {
            final entry = <String, dynamic>{
              'month': ym,
              'income': Planner(state, clock: date).income,
              'cats': [
                for (final c in categories)
                  {
                    'name': c['name'],
                    'type': c['type'],
                    'planned': c['planned'],
                    'actual': ((spent[c['id']] ?? 0) * 100).round() / 100,
                  },
              ],
            };
            final previous = history.where((h) => h['month'] == ym).firstOrNull;
            if (previous == null) {
              history.add(entry);
            } else {
              for (final c in rows(entry['cats'])) {
                final target = rows(previous['cats'])
                    .where(
                      (p) =>
                          p['name'].toString().toLowerCase() ==
                          c['name'].toString().toLowerCase(),
                    )
                    .firstOrNull;
                if (target == null) {
                  (previous['cats'] as List).add(c);
                } else {
                  for (final dynamic original in previous['cats']) {
                    if (original['name'] == target['name']) {
                      original['actual'] =
                          number(original['actual']) + number(c['actual']);
                      original['planned'] = c['planned'];
                    }
                  }
                }
              }
              previous['income'] = entry['income'];
            }
          }
        }
        date = DateTime(date.year, date.month + 1, 1);
        from = isoDate(date);
      }
      history.sort(
        (a, b) => a['month'].toString().compareTo(b['month'].toString()),
      );
      state['history'] = history.length > 36
          ? history.sublist(history.length - 36)
          : history;
      final previousMonth = isoDate(
        DateTime(now.year, now.month - 1, 1),
      ).substring(0, 7);
      for (final dynamic c in categories) {
        if (c['carry'] != true) {
          c.remove('carryIn');
          continue;
        }
        final spent = expenses
            .where(
              (e) =>
                  e['categoryId'] == c['id'] &&
                  (e['date'] as String).startsWith(previousMonth),
            )
            .fold<double>(0, (v, e) => v + number(e['amount']));
        final left =
            number(c['planned']) +
            (previousMonth == old ? number(c['carryIn']) : 0) -
            spent;
        if (left > 0.004) {
          c['carryIn'] = (left * 100).round() / 100;
        } else {
          c.remove('carryIn');
        }
      }
      meta['periodStart'] = '$month-01';
      meta['closedEarly'] = '';
      meta['budgetMonth'] = month;
      changed = true;
    }
  }
  return changed;
}
