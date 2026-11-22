part of 'app.dart';

extension _AdvancedScreens on _PlannerShellState {
  static const tabs = {
    'travel': [('planner', 'Trip planner')],
    'dashboard': [
      ('overview', 'Overview'),
      ('forecast', 'Run-out forecast'),
      ('semester', 'Semester'),
      ('calendar', 'Calendar'),
      ('charts', 'Charts'),
    ],
    'spend': [
      ('log', 'Expense log'),
      ('categories', 'Categories'),
      ('insights', 'Insights & Heatmap'),
      ('recurring', 'Recurring'),
      ('cash', 'Cash'),
    ],
    'budget': [
      ('plan', 'Plan'),
      ('where', 'Where did it go?'),
      ('yearly', 'Yearly / Semester fees'),
      ('history', 'History'),
    ],
    'split': [
      ('ious', 'IOUs & Roommates'),
      ('groups', 'Live Groups'),
      ('history', 'Settled'),
    ],
    'goals': [
      ('savings', 'Savings'),
      ('goals', 'Goals'),
      ('wishlist', 'Wishlist'),
      ('challenges', 'Challenges'),
      ('gifts', 'Gifts'),
    ],
    'debt': [
      ('debts', 'Debts'),
      ('plan', 'Payoff plan'),
      ('emi', 'Loan calculator'),
    ],
    'wallet': [
      ('cash', 'Cash'),
      ('ious', 'IOUs'),
      ('subs', 'Subscriptions'),
      ('transport', 'Transport'),
      ('income', 'Income'),
      ('records', 'Records'),
    ],
    'settings': [
      ('general', 'Basics'),
      ('money', 'Money'),
      ('data', 'Data'),
      ('help', 'Help'),
    ],
  };
  String get route => _PlannerShellState.routeNames[selected];
  String get tab => tabs[route]!.any((t) => t.$1 == widget.tab)
      ? widget.tab
      : tabs[route]!.first.$1;
  Widget sectionTabs() => SingleChildScrollView(
    key: const Key('section-tabs'),
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final item in tabs[route]!)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(tr(item.$2)),
              selected: tab == item.$1,
              onSelected: (_) => context.go('/$route/${item.$1}'),
            ),
          ),
      ],
    ),
  );
  List<Widget> sectionContent() => switch ('$route/$tab') {
    'travel/planner' => [
      TravelSection(store: store, backend: widget.sync?.backend),
    ],
    'settings/general' ||
    'settings/money' ||
    'settings/data' ||
    'settings/help' => settingsPage(),
    'wallet/cash' ||
    'wallet/ious' ||
    'wallet/subs' ||
    'wallet/transport' ||
    'wallet/income' ||
    'wallet/records' => walletPage(),
    'dashboard/overview' => today(),
    'dashboard/forecast' => forecast(),
    'dashboard/semester' => semester(),
    'dashboard/calendar' => calendar(),
    'dashboard/charts' => charts(),
    'spend/log' => [importControls(), ...spend()],
    'spend/categories' => categoryBreakdown(),
    'spend/insights' => insights(),
    'spend/recurring' => [budget()[3]],
    'spend/cash' => wallet(),
    'budget/where' => categoryBreakdown(),
    'budget/yearly' => [budget().last, ...semester()],
    'budget/history' => historyView(),
    'split/groups' => groupsView(),
    'split/history' => settledView(),
    'goals/savings' => savingsSummary(),
    'goals/goals' => [goals().first],
    'goals/wishlist' => [goals().last],
    'goals/challenges' => challengesView(),
    'goals/gifts' => [goals()[1]],
    'debt/plan' => payoffPlannerView(),
    'debt/emi' => loanCalculatorView(),
    _ => [
      today,
      spend,
      budget,
      split,
      goals,
      debt,
      wallet,
      settings,
    ][selected](),
  };
  Widget commandBar() => box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ask AI or log a spend',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            hintText: 'spent 120 on food · can I afford 1500?',
            suffixIcon: Icon(Icons.bolt_outlined),
          ),
          onSubmitted: runCommand,
        ),
        const SizedBox(height: 8),
        const Text('Simple spending and affordability commands work offline.'),
      ],
    ),
  );
  Future<void> runCommand(String text) async {
    final value = text.toLowerCase();
    final amount = double.tryParse(
      (RegExp(r'\d+(?:\.\d{1,2})?').firstMatch(value)?.group(0) ?? ''),
    );
    if (amount != null &&
        RegExp(r'^(spent|paid|bought|spend)\b').hasMatch(value)) {
      final category =
          planner.categories
              .where((c) => value.contains((c['name'] as String).toLowerCase()))
              .firstOrNull ??
          planner.categories.where((c) => c['type'] == 'wants').firstOrNull ??
          planner.categories.first;
      await edit(
        'budget.expenses',
        'Review spend',
        expenseFields,
        row: {
          'id': newId(),
          'amount': amount,
          'categoryId': category['id'],
          'date': isoDate(DateTime.now()),
          'note': text,
        },
      );
      return;
    }
    if (amount != null && RegExp(r'afford|buy|left').hasMatch(value)) {
      message(
        amount <= planner.leftToday
            ? '${money(amount)} fits today’s remaining ${money(planner.leftToday)}.'
            : '${money(amount)} exceeds today’s ${money(planner.leftToday)}. Period balance: ${money(planner.balance)}.',
      );
      return;
    }
    final sync = widget.sync;
    if (sync == null || !sync.online || !sync.backend.configured) {
      message('Offline commands: spent 120 on food; can I afford 1500?');
      return;
    }
    await act(() async {
      final response = await sync.backend.request(
        '/functions/v1/ai',
        method: 'POST',
        auth: false,
        body: {
          'task': 'command',
          'input': {
            'text': text,
            'today': planner.today,
            'context': {
              'monthlyIncome': planner.income.round(),
              'safeToSpend': planner.leftToday.round(),
              'balance': planner.balance.round(),
            },
          },
        },
      );
      message(
        response is Map
            ? response['reply']?.toString() ??
                  'Try a spending or affordability command.'
            : 'No reply returned.',
      );
    });
  }

  List<Widget> categoryBreakdown() => [
    for (final c in planner.categories)
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c['name'].toString(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: number(c['planned']) > 0
                  ? (planner.actual(c['id']) / number(c['planned'])).clamp(
                      0.0,
                      1.0,
                    )
                  : 0,
            ),
            const SizedBox(height: 12),
            Text(
              '${money(planner.actual(c['id']))} spent of ${money(c['planned'])} planned',
            ),
          ],
        ),
      ),
  ];
  List<Widget> charts() => [
    label('Planned versus spent'),
    ...categoryBreakdown(),
    label('Last six months'),
    for (var n = 5; n >= 0; n--)
      box(
        Builder(
          builder: (_) {
            final month = isoDate(
              DateTime(DateTime.now().year, DateTime.now().month - n, 1),
            ).substring(0, 7);
            final total = planner.expenses
                .where((e) => e['date'].toString().startsWith(month))
                .fold<double>(0, (s, e) => s + number(e['amount']));
            return Row(
              children: [
                Expanded(child: Text(month)),
                Text(money(total)),
              ],
            );
          },
        ),
      ),
  ];
  List<Widget> forecast() {
    final p = planner;
    final monthDays = math.max(1, DateTime.now().day);
    final daily = p.spent / monthDays;
    final days = daily > 0
        ? (math.max(0, p.balance - p.reserved) / daily).floor()
        : null;
    return [
      stat(
        'Money at current pace',
        days == null ? 'No spending baseline' : '$days days',
        subtitle: '${money(daily)} per day so far',
      ),
      box(
        Text(
          days != null && days < p.period.days
              ? 'At this pace, money runs out before the next period. Reduce wants or add income.'
              : 'Your current spending pace lasts through this period.',
        ),
      ),
      collection(
        'settings.habits',
        'Spending habits',
        const [
          Field('name', 'Habit'),
          Field('amount', 'Cost each time', numeric: true),
          Field('times', 'Times per week', numeric: true),
        ],
        amountKey: 'amount',
        detail: (h) =>
            '${h['times']} times a week · ${money(number(h['amount']) * number(h['times']) / 7)} per day',
      ),
      label('Day-by-day balance'),
      for (var day = 0; day <= math.min(60, p.period.days); day++)
        box(
          Row(
            children: [
              Expanded(
                child: Text(isoDate(DateTime.now().add(Duration(days: day)))),
              ),
              Text(
                money(
                  p.balance -
                      daily * day -
                      p.dueBills
                          .where(
                            (b) =>
                                b.date.compareTo(
                                  isoDate(
                                    DateTime.now().add(Duration(days: day)),
                                  ),
                                ) <=
                                0,
                          )
                          .fold<double>(
                            0,
                            (s, b) => s + number(b.item['amount']),
                          ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> semester() {
    final sem = (state['student']['semester'] as Map?) ?? {};
    final start = DateTime.tryParse(sem['start']?.toString() ?? ''),
        end = DateTime.tryParse(sem['end']?.toString() ?? '');
    final months = start != null && end != null
        ? math.max(1, (end.year - start.year) * 12 + end.month - start.month)
        : 1;
    final planned = planner.categories.fold<double>(
      0,
      (v, c) => v + number(c['planned']),
    );
    final heavy = rows(
      sem['heavyMonths'],
    ).fold<double>(0, (v, h) => v + number(h['amount']));
    return [
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${sem['start'] ?? 'Start'} – ${sem['end'] ?? 'End'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton(
              onPressed: () async {
                final r = await editRecord(context, 'Semester dates', const [
                  Field('start', 'Start', date: true),
                  Field('end', 'End', date: true),
                ], record: Map<String, dynamic>.from(sem));
                if (r == null) return;
                if (r['end'].compareTo(r['start']) < 0) {
                  message('End date must follow start date.');
                  return;
                }
                await act(
                  () => store.mutate((s) {
                    s['student']['semester'] = {
                      ...r,
                      'heavyMonths': sem['heavyMonths'] ?? [],
                    };
                  }),
                );
              },
              child: const Text('Edit semester'),
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 16,
        children: [
          stat('Income', money(planner.income * months)),
          stat('Base expenses', money(planned * months)),
          stat('Fees and spikes', money(heavy)),
          stat(
            'Projected balance',
            money((planner.income - planned) * months - heavy),
          ),
        ],
      ),
      collection(
        'student.semester.heavyMonths',
        'Semester expenses',
        const [
          Field('name', 'Event / fee'),
          Field('month', 'Month (YYYY-MM)'),
          Field('amount', 'Amount', numeric: true),
        ],
        amountKey: 'amount',
        detail: (r) => r['month'].toString(),
      ),
    ];
  }

  List<Widget> calendar() => [
    label('Bills and deadlines'),
    for (final bill in planner.dueBills)
      box(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(bill.item['name'].toString()),
          subtitle: Text(bill.date),
          trailing: Text(money(bill.item['amount'])),
        ),
      ),
    collection(
      'wallet.deadlines',
      'Deadlines',
      const [Field('title', 'Title'), Field('date', 'Date', date: true)],
      nameKey: 'title',
      detail: (r) => r['date'].toString(),
    ),
  ];
  List<Widget> insights() {
    final byDate = <String, double>{};
    for (final e in planner.expenses) {
      byDate[e['date']] = (byDate[e['date']] ?? 0) + number(e['amount']);
    }
    return [
      label('Last 12 weeks'),
      box(
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (var n = 83; n >= 0; n--)
              Builder(
                builder: (_) {
                  final date = isoDate(
                        DateTime.now().subtract(Duration(days: n)),
                      ),
                      amount =
                          byDate[isoDate(
                            DateTime.now().subtract(Duration(days: n)),
                          )] ??
                          0;
                  return Tooltip(
                    message: '$date · ${money(amount)}',
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: amount == 0
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : Theme.of(context).colorScheme.primary.withValues(
                                alpha: .3 + math.min(.7, amount / 1000),
                              ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      ...categoryBreakdown(),
    ];
  }

  List<Widget> historyView() => [
    FilledButton(
      onPressed: () => act(
        () => store.mutate((s) {
          final month = planner.today.substring(0, 7);
          s['history'] = [
            ...rows(s['history']).where((h) => h['month'] != month),
            {
              'month': month,
              'income': planner.income,
              'cats': [
                for (final c in planner.categories)
                  {...c, 'actual': planner.actual(c['id'])},
              ],
            },
          ];
        }),
      ),
      child: const Text('Save current month snapshot'),
    ),
    for (final h in rows(state['history']).reversed)
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              h['month'].toString(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('Income ${money(h['income'])}'),
            for (final c in rows(h['cats']))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${c['name']} · ${money(c['actual'])} / ${money(c['planned'])}',
                ),
              ),
          ],
        ),
      ),
  ];
  List<Widget> savingsSummary() {
    final total = rows(
      state['goals'],
    ).fold<double>(0, (s, g) => s + number(g['saved']));
    final needs = planner.categories
        .where((c) => c['type'] == 'needs')
        .fold<double>(0, (s, c) => s + number(c['planned']));
    return [
      stat('Saved for your goals', money(total)),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('Emergency fund'),
            Text(
              'Suggested first target: one month of needs, ${money(needs)}.',
            ),
            TextButton(
              onPressed: () => act(
                () => store.put('goals', {
                  'id': newId(),
                  'name': 'Emergency fund',
                  'target': needs,
                  'saved': 0,
                  'contributions': [],
                  'deadline': '',
                  'rate': 0,
                }),
              ),
              child: const Text('Start an emergency fund'),
            ),
          ],
        ),
      ),
      ...goals().take(1),
    ];
  }

  List<Widget> challengesView() => [
    collection(
      'challenges',
      'Challenges',
      const [
        Field(
          'type',
          'Challenge',
          choices: {
            'week52': '52-week savings',
            'nocat': 'Skip a category',
            'cap': 'Spending cap',
          },
        ),
        Field('start', 'Start date', date: true),
        Field('days', 'Duration in days', numeric: true, max: 365),
        Field('cap', 'Spending cap', numeric: true),
        Field('unit', 'Weekly savings increment', numeric: true),
      ],
      nameKey: 'type',
      detail: (r) => '${r['start']} · ${r['days']} days',
      actions: (r) => [
        TextButton(
          onPressed: () =>
              act(() => store.put('challenges', {...r, 'rewarded': true})),
          child: const Text('Mark complete'),
        ),
      ],
    ),
  ];
  List<Widget> settledView() => [
    for (final row
        in store.collection('wallet.ious').where((r) => r['settled'] == true))
      box(
        ListTile(
          title: Text(row['person'].toString()),
          subtitle: Text('Settled ${row['settledAt'] ?? ''}'),
          trailing: Text(money(row['amount'])),
        ),
      ),
    if (!store.collection('wallet.ious').any((r) => r['settled'] == true))
      empty('No settled IOUs.'),
  ];
  Widget importControls() => box(
    Wrap(
      spacing: 8,
      children: [
        OutlinedButton(
          onPressed: transactionImport,
          child: const Text('Import statement / SMS'),
        ),
        OutlinedButton(onPressed: scanReceipt, child: Text(tr('Scan receipt'))),
        OutlinedButton(onPressed: exportCsv, child: const Text('Export CSV')),
      ],
    ),
  );
  Future<void> exportCsv() async {
    String cell(dynamic value) => '"${value.toString().replaceAll('"', '""')}"';
    final csv = [
      ['Date', 'Category', 'Note', 'Amount'],
      for (final e in planner.expenses)
        [
          e['date'],
          planner.categoryName(e['categoryId']),
          e['note'] ?? '',
          e['amount'],
        ],
    ].map((r) => r.map(cell).join(',')).join('\r\n');
    await act(() async {
      await saveBackupFile('heist-expenses-${planner.today}.csv', csv);
    });
  }

  List<Widget> groupsView() => [
    box(
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            onPressed: () => groupSetup(false),
            child: const Text('Create group'),
          ),
          OutlinedButton(
            onPressed: () => groupSetup(true),
            child: const Text('Join group'),
          ),
          TextButton(
            onPressed: () => widget.groups?.synchronize(),
            child: const Text('Refresh groups'),
          ),
        ],
      ),
    ),
    if (widget.groups?.error != null) box(Text(widget.groups!.error!)),
    for (final g in rows(state['groups']))
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              g['name'].toString(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('Join code ${g['joinCode']}'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => addGroupExpense(g),
              child: const Text('Add shared expense'),
            ),
            const SizedBox(height: 12),
            for (final member in rows(
              (state['groupData'] as Map?)?[g['id']]?['members'],
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(member['name'].toString()),
              ),
            for (final balance in groupBalances(
              Map<String, dynamic>.from(
                (state['groupData'] as Map?)?[g['id']] ?? {},
              ),
            ))
              Text(
                '${balance['name']}: ${money(number(balance['netMinor']) / 100)} net',
              ),
            for (final transfer in groupTransfers(
              Map<String, dynamic>.from(
                (state['groupData'] as Map?)?[g['id']] ?? {},
              ),
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${transfer['fromName']} pays ${transfer['toName']} ${money(number(transfer['amountMinor']) / 100)}',
                ),
                trailing: transfer['from'] == g['myMemberId']
                    ? TextButton(
                        onPressed: () => recordGroupSettlement(g, transfer),
                        child: const Text('Record paid'),
                      )
                    : null,
              ),
            for (final expense in rows(
              (state['groupData'] as Map?)?[g['id']]?['expenses'],
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(expense['description'].toString()),
                trailing: Text(money(expense['amount'])),
              ),
          ],
        ),
      ),
  ];
  Future<void> groupSetup(bool join) async {
    final service = widget.groups;
    if (service == null) {
      message('Group service is unavailable.');
      return;
    }
    final value =
        await editRecord(context, join ? 'Join group' : 'Create group', [
          Field('name', join ? 'Join code' : 'Group name'),
          const Field('member', 'Your name in this group'),
        ]);
    if (value == null) return;
    await act(
      () => join
          ? service.join(value['name'], value['member'])
          : service.create(value['name'], value['member']),
    );
  }

  Future<void> recordGroupSettlement(Json group, Json transfer) async {
    if (!await confirm(
      context,
      'Record group payment?',
      'Confirm you already paid ${transfer['toName']} ${money(number(transfer['amountMinor']) / 100)}. This records a settlement; it does not transfer money.',
    ))
      return;
    await act(
      () => widget.groups!.addExpense(
        group,
        'Settlement: ${transfer['fromName']} paid ${transfer['toName']}',
        number(transfer['amountMinor']) / 100,
        {transfer['to'] as String: transfer['amountMinor'] as int},
        categoryChoices.keys.first,
      ),
    );
  }

  Future<void> addGroupExpense(Json group) async {
    final service = widget.groups;
    if (service == null) return;
    final members = rows(
      (state['groupData'] as Map?)?[group['id']]?['members'],
    );
    if (members.isEmpty) {
      message('Connect once to load this group’s members.');
      return;
    }
    final value = await editRecord(context, 'Shared expense (equal split)', [
      const Field('description', 'Description'),
      const Field('amount', 'Total amount', numeric: true),
      Field('categoryId', 'Your budget category', choices: categoryChoices),
    ]);
    if (value == null) return;
    final cents = (number(value['amount']) * 100).round();
    final shares = <String, int>{
      for (var i = 0; i < members.length; i++)
        members[i]['id'] as String:
            cents ~/ members.length + (i < cents % members.length ? 1 : 0),
    };
    await act(
      () => service.addExpense(
        group,
        value['description'],
        cents / 100,
        shares,
        value['categoryId'],
      ),
    );
  }
}
