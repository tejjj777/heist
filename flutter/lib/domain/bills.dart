/// All monetary allocation occurs in integer cents. Charges follow item shares.
Map<String, int> itemizedShares(
  List<String> people,
  String text, {
  int charges = 0,
}) {
  final shares = {for (final p in people) p: 0};
  if (people.isEmpty || people.toSet().length != people.length || charges < 0)
    throw const FormatException('Invalid people or charges.');
  for (final line in text.split('\n').where((l) => l.trim().isNotEmpty)) {
    final parts = line.split('|').map((p) => p.trim()).toList();
    if (parts.length != 3 || parts[0].isEmpty)
      throw const FormatException(
        'Use Item | Amount | You, Friend for each item.',
      );
    final value = double.tryParse(parts[1].replaceAll(',', ''));
    if (value == null || !value.isFinite || value <= 0)
      throw const FormatException('Item amounts must be positive.');
    final members = parts[2].split(',').map((p) => p.trim()).toSet().toList();
    if (members.isEmpty || members.any((p) => !shares.containsKey(p)))
      throw const FormatException(
        'Assign items only to the listed people, including You.',
      );
    final cents = (value * 100).round();
    for (var n = 0; n < members.length; n++) {
      final p = members[n];
      shares[p] =
          shares[p]! +
          cents ~/ members.length +
          (n < cents % members.length ? 1 : 0);
    }
  }
  final total = shares.values.fold<int>(0, (a, b) => a + b);
  if (total <= 0) throw const FormatException('Enter at least one item.');
  if (charges > 0) {
    final allocated = {
      for (final p in people) p: charges * shares[p]! ~/ total,
    };
    var left = charges - allocated.values.fold<int>(0, (a, b) => a + b);
    final rank = [...people]
      ..sort(
        (a, b) => (charges * shares[b]! % total).compareTo(
          charges * shares[a]! % total,
        ),
      );
    for (final p in rank) {
      if (left-- <= 0) break;
      allocated[p] = allocated[p]! + 1;
    }
    for (final p in people) {
      shares[p] = shares[p]! + allocated[p]!;
    }
  }
  return shares;
}
