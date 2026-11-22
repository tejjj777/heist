import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/backend.dart';
import '../data/backup_file.dart';
import '../data/local_store.dart';
import '../data/travel_agent.dart';
import '../domain/planner.dart';
import '../domain/travel.dart';
import 'editor.dart';

class TravelSection extends StatefulWidget {
  final LocalStore store;
  final HeistBackend? backend;
  const TravelSection({super.key, required this.store, this.backend});
  @override
  State<TravelSection> createState() => _TravelSectionState();
}

class _TravelSectionState extends State<TravelSection> {
  String? selectedId;
  String panel = 'Itinerary', hotelQuery = '';
  bool busy = false, budgetOnly = false;
  String? status;
  LocalStore get store => widget.store;
  Json? get trip => store
      .collection('travelTrips')
      .where((t) => t['id'] == selectedId)
      .firstOrNull;
  String cash(dynamic value) => store.hideAmounts
      ? '••••'
      : '${trip?['currency'] ?? store.state['currency']} ${number(value).toStringAsFixed(2)}';
  void notice(Object e) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      notice(e);
    } finally {
      if (mounted)
        setState(() {
          busy = false;
          status = null;
        });
    }
  }

  Future<void> open(String url) async {
    if (!travelUrl(url)) return;
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication))
      notice('Could not open link.');
  }

  Widget card(List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Future<void> newTrip({bool edit = false}) async {
    final previous = edit ? clone(trip!) : null;
    final row = await editRecord(
      context,
      'Plan a trip',
      const [
        Field('destination', 'Destination'),
        Field('origin', 'Starting city'),
        Field('startDate', 'Departure date', date: true),
        Field('days', 'Days (1–14)', numeric: true, max: 14),
        Field('travelers', 'Travelers (1–30)', numeric: true, max: 30),
        Field('budget', 'Total group budget', numeric: true),
        Field(
          'currency',
          'Currency',
          choices: {'INR': 'INR', 'USD': 'USD', 'EUR': 'EUR', 'GBP': 'GBP'},
        ),
        Field(
          'pace',
          'Pace',
          choices: {
            'relaxed': 'Relaxed',
            'balanced': 'Balanced',
            'packed': 'Packed',
          },
        ),
        Field(
          'interests',
          'Interests, accessibility and stay preferences',
          required: false,
          lines: 3,
        ),
      ],
      record:
          previous ??
          {
            'startDate': isoDate(DateTime.now().add(const Duration(days: 7))),
            'days': 3,
            'travelers': 2,
            'currency': store.state['currency'],
            'pace': 'balanced',
          },
    );
    if (row == null || !mounted) return;
    await run(() async {
      final validated = travelBrief(row);
      if (previous != null &&
          rows(previous['expenses']).isNotEmpty &&
          (previous['travelers'] != validated['travelers'] ||
              previous['currency'] != validated['currency'])) {
        throw const FormatException(
          'Traveler count and currency cannot change after recording expenses. Create another trip.',
        );
      }
      if (previous != null &&
          mounted &&
          !await confirm(
            context,
            'Update trip details?',
            'This resets generated research and itinerary. Expenses are retained; the previous plan remains in local recovery history.',
          ))
        return;
      final id = previous?['id'] ?? newId();
      await store.put('travelTrips', {
        ...validated,
        'id': id,
        'status': 'draft',
        'expenses': previous?['expenses'] ?? [],
        'people':
            previous != null && previous['travelers'] == validated['travelers']
            ? previous['people']
            : [for (var i = 1; i <= validated['travelers']; i++) 'Traveler $i'],
      });
      if (mounted)
        setState(() {
          selectedId = id;
          panel = 'Itinerary';
        });
    });
  }

  Future<void> generate() async {
    final selected = trip;
    if (selected == null) return;
    final backend = widget.backend;
    if (backend == null || !backend.configured || backend.session == null) {
      notice(
        'Sign in under Backup & settings → Data to use live travel research. You can plan and log expenses offline.',
      );
      return;
    }
    if (!await confirm(
      context,
      'Research this trip online?',
      'Destination, dates, traveler count, budget and preferences will be sent to the travel AI and its search provider. Your wallet balances and expense history are excluded.',
    ))
      return;
    await run(
      () => TravelAgent(store, backend).generate(
        selected['id'],
        progress: (text) {
          if (mounted) setState(() => status = text);
        },
      ),
    );
  }

  Future<void> addStop() async {
    final t = trip!;
    final row = await editRecord(context, 'Add itinerary stop', [
      Field(
        'day',
        'Day',
        choices: {for (var i = 1; i <= t['days']; i++) '$i': 'Day $i'},
      ),
      const Field('name', 'Place or activity'),
      const Field('time', 'Time (HH:mm)'),
      const Field('notes', 'Notes', required: false, lines: 2),
      const Field('cost', 'Estimated cost', numeric: true),
    ]);
    if (row == null) return;
    await run(() async {
      final current = clone(trip!);
      final plan = current['plan'] is Map
          ? Map<String, dynamic>.from(current['plan'])
          : <String, dynamic>{
              'days': [
                for (var i = 1; i <= t['days']; i++)
                  {'day': i, 'title': 'Day $i', 'stops': []},
              ],
              'budget': [],
              'hotels': [],
            };
      final days = rows(plan['days']);
      final index = int.parse(row['day']) - 1;
      days[index]['stops'] = [
        ...rows(days[index]['stops']),
        {...row, 'id': newId()},
      ];
      plan['days'] = days;
      await store.put('travelTrips', {...current, 'plan': plan});
    });
  }

  Future<void> expense() async {
    final t = trip!;
    final people = (t['people'] as List).cast<String>();
    final row = await editRecord(context, 'Trip expense', [
      const Field('note', 'What did you pay for?'),
      const Field('amount', 'Amount', numeric: true),
      const Field('date', 'Date', date: true),
      const Field(
        'category',
        'Category',
        choices: {
          'Stay': 'Stay',
          'Food': 'Food',
          'Transport': 'Transport',
          'Activities': 'Activities',
          'Other': 'Other',
        },
      ),
      Field('paidBy', 'Paid by', choices: {for (final p in people) p: p}),
    ]);
    if (row == null) return;
    if (number(row['amount']) <= 0) {
      notice('Enter a positive amount.');
      return;
    }
    await run(
      () => store.put('travelTrips', {
        ...trip!,
        'expenses': [
          ...rows(trip!['expenses']),
          {...row, 'id': newId()},
        ],
      }),
    );
  }

  Future<void> renamePeople() async {
    final t = trip!;
    final people = (t['people'] as List).cast<String>();
    final row = await editRecord(
      context,
      'Travelers',
      [
        for (var i = 0; i < people.length; i++)
          Field('$i', 'Traveler ${i + 1}'),
      ],
      record: {for (var i = 0; i < people.length; i++) '$i': people[i]},
    );
    if (row == null) return;
    final next = [
      for (var i = 0; i < people.length; i++) row['$i'].toString().trim(),
    ];
    if (next.toSet().length != people.length) {
      notice('Use a unique name for each traveler.');
      return;
    }
    await run(() async {
      final expenses = rows(trip!['expenses']);
      for (final e in expenses) {
        final i = people.indexOf(e['paidBy']);
        if (i >= 0) e['paidBy'] = next[i];
      }
      await store.put('travelTrips', {
        ...trip!,
        'people': next,
        'expenses': expenses,
      });
    });
  }

  Future<void> exportTrip() => run(() async {
    // Shared copies intentionally exclude personal expenses and AI error diagnostics.
    final t = clone(trip!)
      ..remove('expenses')
      ..remove('error');
    final saved = await saveBackupFile(
      'heist-trip-${t['id']}.json',
      jsonEncode({'format': 'heist-trip', 'version': 1, 'trip': t}),
    );
    if (saved)
      notice(
        'Trip share opened. Use Backup & settings for a full restorable backup.',
      );
  });
  List<Widget> itinerary(Json t) {
    final plan = t['plan'] as Map?;
    final days = rows(plan?['days']);
    return [
      if (plan?['summary'] != null) card([Text('${plan!['summary']}')]),
      if (days.isEmpty)
        card([
          const Text(
            'Save your trip, then research it online or add stops manually. Drafts and itinerary edits work offline.',
          ),
        ]),
      for (var di = 0; di < days.length; di++)
        card([
          Text(
            'Day ${di + 1} · ${days[di]['title'] ?? ''}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (var si = 0; si < rows(days[di]['stops']).length; si++)
            stopTile(t, days, di, si),
          if (rows(days[di]['stops']).isNotEmpty)
            TextButton.icon(
              onPressed: () => open(dayMap(t, days[di])),
              icon: const Icon(Icons.directions),
              label: const Text('Open day route in Google Maps'),
            ),
        ]),
      OutlinedButton.icon(
        onPressed: busy ? null : addStop,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add stop manually'),
      ),
    ];
  }

  String dayMap(Json t, Json day) {
    final stops = rows(day['stops']);
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${stops.last['name']}, ${t['destination']}',
      if (stops.length > 1)
        'origin': '${stops.first['name']}, ${t['destination']}',
      if (stops.length > 2)
        'waypoints': stops
            .skip(1)
            .take(stops.length - 2)
            .map((s) => '${s['name']}, ${t['destination']}')
            .join('|'),
    }).toString();
  }

  Widget stopTile(Json t, List<Json> days, int di, int si) {
    final stops = rows(days[di]['stops']), s = stops[si];
    Future<void> move(int delta) => run(() async {
      final other = si + delta;
      final item = stops.removeAt(si);
      stops.insert(other, item);
      days[di]['stops'] = stops;
      await store.put('travelTrips', {
        ...trip!,
        'plan': {...Map<String, dynamic>.from(trip!['plan']), 'days': days},
      });
    });
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${s['time'] ?? ''}  ${s['name']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text('${s['notes'] ?? ''}'),
          Text('Estimate: ${cash(s['cost'])}'),
          Wrap(
            children: [
              TextButton(
                onPressed: () => open(
                  Uri.https('www.google.com', '/maps/search/', {
                    'api': '1',
                    'query': '${s['name']}, ${t['destination']}',
                  }).toString(),
                ),
                child: const Text('Map'),
              ),
              if (travelUrl('${s['sourceUrl']}'))
                TextButton(
                  onPressed: () => open(s['sourceUrl']),
                  child: const Text('Source'),
                ),
              IconButton(
                tooltip: 'Move earlier',
                onPressed: busy || si == 0 ? null : () => move(-1),
                icon: const Icon(Icons.arrow_upward, size: 18),
              ),
              IconButton(
                tooltip: 'Move later',
                onPressed: busy || si == stops.length - 1
                    ? null
                    : () => move(1),
                icon: const Icon(Icons.arrow_downward, size: 18),
              ),
              IconButton(
                tooltip: 'Remove stop',
                onPressed: busy
                    ? null
                    : () => run(() async {
                        stops.removeAt(si);
                        days[di]['stops'] = stops;
                        await store.put('travelTrips', {
                          ...trip!,
                          'plan': {
                            ...Map<String, dynamic>.from(trip!['plan']),
                            'days': days,
                          },
                        });
                      }),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  List<Widget> hotels(Json t) {
    final ceiling =
        number(t['budget']) /
        (number(t['days']) < 2 ? 1 : number(t['days']) - 1);
    final matches =
        rows(t['plan']?['hotels'])
            .where(
              (h) => '${h['name']} ${h['area']} ${h['amenities']}'
                  .toLowerCase()
                  .contains(hotelQuery.toLowerCase()),
            )
            .where(
              (h) => !budgetOnly || number(h['nightlyEstimate']) <= ceiling,
            )
            .toList()
          ..sort(
            (a, b) => number(
              a['nightlyEstimate'],
            ).compareTo(number(b['nightlyEstimate'])),
          );
    return [
      card([
        const Text(
          'Compare stays',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Search live prices, guest reviews, taxes and cancellation rules on the provider. Saved estimates are not availability or booking quotes.',
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Filter saved stays by name, area or amenity',
          ),
          onChanged: (v) => setState(() => hotelQuery = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Within total trip budget per night'),
          value: budgetOnly,
          onChanged: (v) => setState(() => budgetOnly = v),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => open(
                Uri.https('www.booking.com', '/searchresults.html', {
                  'ss': t['destination'],
                  'checkin': t['startDate'],
                  'checkout': isoDate(
                    DateTime.parse(
                      t['startDate'],
                    ).add(Duration(days: t['days'] > 1 ? t['days'] - 1 : 1)),
                  ),
                  'group_adults': '${t['travelers']}',
                  'selected_currency': t['currency'],
                }).toString(),
              ),
              child: const Text('Booking.com'),
            ),
            TextButton(
              onPressed: () => open(
                Uri.https('www.tripadvisor.com', '/Search', {
                  'q': '${t['destination']} hotels',
                }).toString(),
              ),
              child: const Text('Tripadvisor'),
            ),
            TextButton(
              onPressed: () => open(
                Uri.https('www.google.com', '/search', {
                  'q':
                      'site:makemytrip.com/hotels/ ${t['destination']} ${t['startDate']} ${t['travelers']} travelers',
                }).toString(),
              ),
              child: const Text('MakeMyTrip search'),
            ),
          ],
        ),
      ]),
      for (final h in matches)
        card([
          Text('${h['name']}', style: Theme.of(context).textTheme.titleMedium),
          Text('${h['area'] ?? ''}'),
          Text('Estimated nightly: ${cash(h['nightlyEstimate'])}'),
          Text('${h['notes'] ?? ''}'),
          if (h['amenities'] is List)
            Text((h['amenities'] as List).join(' · ')),
          if (travelUrl('${h['sourceUrl']}'))
            TextButton(
              onPressed: () => open(h['sourceUrl']),
              child: const Text('Read source / check reviews'),
            ),
        ]),
      if (matches.isEmpty)
        const Text(
          'No saved stays match. Research a trip or compare directly on the providers.',
        ),
    ];
  }

  List<Widget> budget(Json t) => [
    card([
      Text('Trip budget: ${cash(t['budget'])}'),
      Text('Spent: ${cash(travelSpent(t))}'),
      Text('Remaining: ${cash(number(t['budget']) - travelSpent(t))}'),
      const SizedBox(height: 12),
      const Text(
        'Estimated plan costs (whole group)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      for (final item in rows(t['plan']?['budget']))
        Text('${item['category']}: ${cash(item['amount'])}'),
      Text(
        'Estimated total: ${cash(rows(t['plan']?['budget']).fold(0.0, (s, b) => s + number(b['amount'])))}',
      ),
      if (rows(
            t['plan']?['budget'],
          ).fold(0.0, (s, b) => s + number(b['amount'])) >
          number(t['budget']))
        Text(
          'Estimated plan exceeds your group budget. Adjust the trip before booking.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const Text(
        'Trip expenses are separate from your main spending log to avoid double counting.',
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy ? null : expense,
        icon: const Icon(Icons.add),
        label: const Text('Add trip expense'),
      ),
    ]),
    for (final e in rows(t['expenses']).reversed)
      card([
        Text('${e['note']} · ${cash(e['amount'])}'),
        Text('${e['date']} · ${e['category']} · paid by ${e['paidBy']}'),
        TextButton(
          onPressed: busy
              ? null
              : () => run(
                  () => store.put('travelTrips', {
                    ...trip!,
                    'expenses': rows(
                      trip!['expenses'],
                    ).where((x) => x['id'] != e['id']).toList(),
                  }),
                ),
          child: const Text('Remove expense'),
        ),
      ]),
  ];
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final trips = store.collection('travelTrips');
      final t = trip;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card([
            Text(
              'Your next escape, planned.',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Research a destination, build a route, compare stays and track every shared expense.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : newTrip,
              icon: const Icon(Icons.travel_explore),
              label: const Text('New trip'),
            ),
            if (trips.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(selectedId),
                initialValue: t?['id'],
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Saved trips'),
                items: [
                  for (final item in trips)
                    DropdownMenuItem(
                      value: item['id'] as String,
                      child: Text(
                        '${item['destination']} · ${item['startDate']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (id) => setState(() => selectedId = id),
              ),
            ],
          ]),
          if (t != null) ...[
            card([
              Text(
                '${t['destination']} · ${t['days']} days · ${t['travelers']} travelers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('${t['origin']} → ${t['destination']} · ${t['startDate']}'),
              Text('Group budget: ${cash(t['budget'])}'),
              const Text(
                'Saved on this device. Online research requires sign-in. Maps and live booking pages require internet.',
              ),
              if (busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                Text(status ?? 'Saving…'),
              ],
              if (t['error'] != null)
                Text(
                  '${t['error']}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : generate,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      t['research'] == null
                          ? 'Research & build trip'
                          : 'Resume / rebuild plan',
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => newTrip(edit: true),
                    child: const Text('Edit trip details'),
                  ),
                  TextButton(
                    onPressed: busy ? null : exportTrip,
                    child: const Text('Share itinerary'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            if (await confirm(
                              context,
                              'Delete trip?',
                              'A recovery copy remains in Backup & settings.',
                            )) {
                              await store.remove('travelTrips', t['id']);
                              if (mounted) setState(() => selectedId = null);
                            }
                          }),
                    child: const Text('Delete trip'),
                  ),
                ],
              ),
            ]),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final name in [
                    'Itinerary',
                    'Stays',
                    'Budget',
                    'Group',
                    'Sources',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(name),
                        selected: panel == name,
                        onSelected: (_) => setState(() => panel = name),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (panel == 'Itinerary') ...itinerary(t),
            if (panel == 'Stays') ...hotels(t),
            if (panel == 'Budget') ...budget(t),
            if (panel == 'Group')
              card([
                const Text(
                  'Split costs equally',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Positive balance = should receive; negative = owes. These are local calculations, not payments. Share exports are copies; simultaneous group editing is not enabled.',
                ),
                for (final e in travelBalances(t).entries)
                  Text('${e.key}: ${cash(e.value)}'),
                TextButton(
                  onPressed: busy ? null : renamePeople,
                  child: const Text('Name travelers'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : exportTrip,
                  child: const Text('Share itinerary copy'),
                ),
              ]),
            if (panel == 'Sources')
              card([
                Text(
                  'Research updated: ${t['research']?['researchedAt'] ?? 'Not researched'}',
                ),
                const Text(
                  'Open source pages to check current details. AI estimates can be wrong. Reviews and rates are not copied from booking providers.',
                ),
                if (t['research']?['summary'] != null)
                  SelectableText('${t['research']['summary']}'),
                for (final s in rows(t['research']?['sources']))
                  TextButton(
                    onPressed: () => open('${s['url']}'),
                    child: Text('${s['title']}\n${s['url']}'),
                  ),
                for (final w in (t['plan']?['warnings'] as List? ?? []))
                  Text('• $w'),
              ]),
          ],
        ],
      );
    },
  );
}
