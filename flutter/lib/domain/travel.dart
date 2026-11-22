import 'planner.dart';

Json travelBrief(Json input) {
  final start = input['startDate']?.toString() ?? '';
  final days = number(input['days']).toInt();
  final travelers = number(input['travelers']).toInt();
  final destination = input['destination']?.toString().trim() ?? '';
  if (destination.isEmpty ||
      destination.length > 150 ||
      !validDate(start) ||
      days < 1 ||
      days > 14 ||
      travelers < 1 ||
      travelers > 30 ||
      number(input['budget']) <= 0 ||
      number(input['budget']) > 100000000 ||
      !RegExp(r'^[A-Z]{3}$').hasMatch(input['currency']?.toString() ?? '')) {
    throw const FormatException(
      'Enter a destination, valid date, 1–14 days, 1–30 travelers and a positive budget.',
    );
  }
  return {
    ...input,
    'destination': destination,
    'days': days,
    'travelers': travelers,
  };
}

bool travelUrl(String url) {
  final u = Uri.tryParse(url);
  return u != null &&
      u.scheme == 'https' &&
      u.host.contains('.') &&
      u.userInfo.isEmpty;
}

Json travelPlan(dynamic value, int days) {
  if (value is! Map) throw const FormatException('Invalid itinerary.');
  final plan = Map<String, dynamic>.from(value);
  final itinerary = rows(plan['days']);
  if (itinerary.length != days ||
      plan['budget'] is! List ||
      itinerary.any(
        (d) => d['stops'] is! List || rows(d['stops']).length > 12,
      )) {
    throw const FormatException(
      'Incomplete itinerary. Research is saved; retry planning.',
    );
  }
  for (final item in [
    ...rows(plan['budget']),
    ...rows(plan['hotels']),
    ...itinerary.expand((d) => rows(d['stops'])),
  ]) {
    for (final key in ['amount', 'cost', 'nightlyEstimate']) {
      if (item.containsKey(key) &&
          (item[key] is! num ||
              !(item[key] as num).isFinite ||
              (item[key] as num) < 0)) {
        throw const FormatException('Invalid travel cost.');
      }
    }
  }
  return plan;
}

double travelSpent(Json trip) =>
    rows(trip['expenses']).fold(0.0, (s, e) => s + number(e['amount']));

// Each expense is split equally among the trip's named participants.
Map<String, double> travelBalances(Json trip) {
  final people = (trip['people'] as List? ?? []).whereType<String>().toSet();
  final balances = {for (final p in people) p: 0.0};
  if (people.isEmpty) return balances;
  for (final expense in rows(trip['expenses'])) {
    final payer = expense['paidBy'];
    if (!people.contains(payer)) continue;
    final minor = (number(expense['amount']) * 100).round();
    balances[payer] = balances[payer]! + minor / 100;
    var index = 0;
    for (final p in people) {
      final share =
          minor ~/ people.length + (index++ < minor % people.length ? 1 : 0);
      balances[p] = balances[p]! - share / 100;
    }
  }
  return balances;
}
