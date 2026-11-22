import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/backup_codec.dart';
import '../data/sync_engine.dart';
import '../data/group_service.dart';
import '../data/ocr.dart';
import '../data/backup_file.dart';
import '../data/local_store.dart';
import '../domain/planner.dart';
import '../domain/finance.dart';
import '../domain/imports.dart';
import '../domain/bills.dart';
import '../domain/groups.dart';
import 'editor.dart';
import 'translations.dart';
import 'travel_section.dart';
part 'advanced.dart';
part 'tools_screens.dart';
part 'account_tools.dart';
part 'preferences_screens.dart';

class HeistApp extends StatefulWidget {
  final LocalStore store;
  final SyncEngine? sync;
  final GroupService? groups;
  const HeistApp({super.key, required this.store, this.sync, this.groups});
  @override
  State<HeistApp> createState() => _HeistAppState();
}

class _HeistAppState extends State<HeistApp> {
  late final GoRouter router = GoRouter(
    initialLocation: '/dashboard/overview',
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/dashboard/overview'),
      GoRoute(
        path: '/:section',
        builder: (_, s) => PlannerShell(
          store: widget.store,
          sync: widget.sync,
          groups: widget.groups,
          section: s.pathParameters['section']!,
          tab: '',
        ),
      ),
      GoRoute(
        path: '/:section/:tab',
        builder: (_, s) => PlannerShell(
          store: widget.store,
          sync: widget.sync,
          groups: widget.groups,
          section: s.pathParameters['section']!,
          tab: s.pathParameters['tab']!,
        ),
      ),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final dark = widget.store.dark;
      return MaterialApp.router(
        routerConfig: router,
        title: 'HEIST',
        locale: Locale(widget.store.language),
        supportedLocales: const [Locale('en'), Locale('te'), Locale('hi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'DMSans',
          fontFamilyFallback: const ['NotoTelugu', 'NotoHindi'],
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF9270ED),
            brightness: dark ? Brightness.dark : Brightness.light,
            surface: dark ? const Color(0xFF2C2745) : const Color(0xFFF7F6FC),
          ),
          scaffoldBackgroundColor: dark
              ? const Color(0xFF201C34)
              : const Color(0xFFF7F6FC),
          textTheme: TextTheme(
            displayMedium: TextStyle(
              fontFamily: widget.store.language == 'en'
                  ? 'HeistDisplay'
                  : widget.store.language == 'te'
                  ? 'NotoTelugu'
                  : 'NotoHindi',
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w800,
            ),
            headlineLarge: TextStyle(
              fontFamily: widget.store.language == 'en'
                  ? 'HeistDisplay'
                  : widget.store.language == 'te'
                  ? 'NotoTelugu'
                  : 'NotoHindi',
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w800,
            ),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
      );
    },
  );
}

class PlannerShell extends StatefulWidget {
  final LocalStore store;
  final SyncEngine? sync;
  final GroupService? groups;
  final String section, tab;
  const PlannerShell({
    super.key,
    required this.store,
    this.sync,
    this.groups,
    this.section = 'dashboard',
    this.tab = 'overview',
  });
  @override
  State<PlannerShell> createState() => _PlannerShellState();
}

class _PlannerShellState extends State<PlannerShell> {
  int selected = 0;
  bool working = false;
  String search = '';
  String walletSearch = '', walletRange = 'all', walletDirection = 'all';
  final walletSearchController = TextEditingController();
  bool tutorialScheduled = false;
  String tr(String text) => translate(store.language, text);
  static const routeNames = [
    'dashboard',
    'spend',
    'budget',
    'split',
    'goals',
    'debt',
    'wallet',
    'settings',
    'travel',
  ];
  @override
  void initState() {
    super.initState();
    widget.store.addListener(refreshView);
    widget.sync?.addListener(refreshView);
    widget.groups?.addListener(refreshView);
    selected = math.max(0, routeNames.indexOf(widget.section));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted && store.preferences.get('tutorial.v1') != true)
        await showTutorial();
      if (mounted) await recoverReceiptCapture();
    });
  }

  void refreshView() {
    if (mounted) setState(() {});
  }

  void updateView(VoidCallback update) {
    if (mounted) setState(update);
  }

  @override
  void dispose() {
    walletSearchController.dispose();
    widget.store.removeListener(refreshView);
    widget.sync?.removeListener(refreshView);
    widget.groups?.removeListener(refreshView);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlannerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(refreshView);
      widget.store.addListener(refreshView);
    }
    if (oldWidget.sync != widget.sync) {
      oldWidget.sync?.removeListener(refreshView);
      widget.sync?.addListener(refreshView);
    }
    if (oldWidget.groups != widget.groups) {
      oldWidget.groups?.removeListener(refreshView);
      widget.groups?.addListener(refreshView);
    }
    selected = math.max(0, routeNames.indexOf(widget.section));
  }

  void navigate(int index) {
    context.go('/${routeNames[index]}');
  }

  LocalStore get store => widget.store;
  Json get state => store.state;
  Planner get planner => Planner(state);
  static const destinations = [
    ('Today', Icons.dashboard_outlined),
    ('Spend', Icons.receipt_long_outlined),
    ('Budget', Icons.pie_chart_outline),
    ('Split', Icons.people_outline),
    ('Goals', Icons.flag_outlined),
    ('Debt', Icons.account_balance_outlined),
    ('Wallet', Icons.account_balance_wallet_outlined),
    ('Backup & settings', Icons.settings_outlined),
    ('Travel Agent', Icons.travel_explore),
  ];
  String money(dynamic amount) => store.hideAmounts
      ? '••••'
      : NumberFormat.simpleCurrency(
          name: state['currency']?.toString() ?? 'INR',
          decimalDigits: 2,
        ).format(number(amount));
  void message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> act(Future<void> Function() work) async {
    if (working) return;
    setState(() => working = true);
    try {
      await work();
    } catch (e) {
      message('Operation failed: $e');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Widget box(Widget child, {Color? color}) => Container(
    margin: const EdgeInsets.only(bottom: 20, right: 5),
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .8),
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .8),
          offset: const Offset(4, 5),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 22,
        ),
        child: child,
      ),
    ),
  );
  Widget label(String value) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 12),
    child: Text(value, style: Theme.of(context).textTheme.titleLarge),
  );
  Widget empty(String text) =>
      box(Padding(padding: const EdgeInsets.all(16), child: Text(text)));
  Widget stat(String title, String value, {String? subtitle}) => SizedBox(
    width: math.min(260, MediaQuery.sizeOf(context).width - 42),
    child: box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 12),
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          if (subtitle != null) ...[const SizedBox(height: 8), Text(subtitle)],
        ],
      ),
    ),
  );
  Map<String, String> get categoryChoices => {
    for (final c in planner.categories) c['id'] as String: c['name'].toString(),
  };
  Future<void> edit(
    String path,
    String title,
    List<Field> fields, {
    Json? row,
  }) async {
    final next = await editRecord(context, title, fields, record: row);
    if (next == null) return;
    await act(() => store.put(path, next));
  }

  Future<void> delete(String path, Json row) async {
    if (await confirm(
      context,
      'Delete this record?',
      'A recent copy remains available under Backup & settings.',
    )) {
      await act(() => store.remove(path, row['id'] as String));
    }
  }

  Widget collection(
    String path,
    String title,
    List<Field> fields, {
    String nameKey = 'name',
    String? amountKey,
    String Function(Json)? detail,
    List<Widget> Function(Json)? actions,
    bool canDelete = true,
  }) {
    final entries = store
        .collection(path)
        .where((row) => selected != 6 || walletMatches(path, row))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          children: [
            label(title),
            TextButton.icon(
              onPressed: working
                  ? null
                  : () => edit(path, 'Add $title', fields),
              icon: const Icon(Icons.add),
              label: Text(tr('Add')),
            ),
          ],
        ),
        if (entries.isEmpty)
          empty(
            selected == 6
                ? tr('No records match these filters.')
                : 'No records yet. Add one to start.',
          ),
        for (final row in entries)
          box(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row[nameKey]?.toString() ?? title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (amountKey != null)
                      Flexible(
                        child: Text(
                          money(row[amountKey]),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                  ],
                ),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(detail(row)),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: working
                          ? null
                          : () => edit(path, 'Edit $title', fields, row: row),
                      child: Text(tr('Edit')),
                    ),
                    if (canDelete)
                      TextButton(
                        onPressed: working ? null : () => delete(path, row),
                        child: Text(tr('Delete')),
                      ),
                    ...?actions?.call(row),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 950;
    return Scaffold(
      bottomNavigationBar: wide
          ? null
          : Builder(
              builder: (scaffoldContext) => NavigationBar(
                selectedIndex: [0, 1, 6].contains(selected)
                    ? [0, 1, 6].indexOf(selected)
                    : 3,
                onDestinationSelected: (i) => i == 3
                    ? Scaffold.of(scaffoldContext).openDrawer()
                    : navigate([0, 1, 6][i]),
                destinations: [
                  for (final i in [0, 1, 6, 7])
                    NavigationDestination(
                      icon: Icon(i == 7 ? Icons.menu : destinations[i].$2),
                      label: tr(i == 7 ? 'More' : destinations[i].$1),
                    ),
                ],
              ),
            ),
      appBar: AppBar(
        title: Image.asset(
          'assets/heist-logo.png',
          height: wide ? 42 : 32,
          semanticLabel: 'HEIST',
        ),
        actions: [
          if (widget.sync != null)
            ListenableBuilder(
              listenable: widget.sync!,
              builder: (context, _) => TextButton.icon(
                onPressed: () => navigate(7),
                icon: Icon(
                  !widget.sync!.online
                      ? Icons.cloud_off
                      : widget.sync!.busy
                      ? Icons.sync
                      : widget.sync!.error != null
                      ? Icons.sync_problem
                      : Icons.cloud_done_outlined,
                ),
                label: Text(
                  wide
                      ? '${widget.sync!.online ? 'Online' : 'Offline'} · ${widget.sync!.pending} pending'
                      : '${widget.sync!.pending}',
                ),
              ),
            ),
          IconButton(
            tooltip: tr(store.hideAmounts ? 'Show amounts' : 'Hide amounts'),
            onPressed: () => act(
              () => store.setPreference('hideAmounts', !store.hideAmounts),
            ),
            icon: Icon(
              store.hideAmounts
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          IconButton(
            tooltip: tr('Scan receipt'),
            onPressed: working ? null : scanReceipt,
            icon: const Icon(Icons.document_scanner_outlined),
          ),
          if (wide)
            IconButton(
              tooltip: 'Toggle dark mode',
              onPressed: () => act(() => store.setDark(!store.dark)),
              icon: Icon(
                store.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
        ],
      ),
      drawer: wide
          ? null
          : Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(tr('Your money. Your move.')),
                    ),
                    for (var i = 0; i < destinations.length; i++)
                      ListTile(
                        selected: selected == i,
                        leading: Icon(destinations[i].$2),
                        title: Text(tr(destinations[i].$1)),
                        onTap: () {
                          Navigator.pop(context);
                          navigate(i);
                        },
                      ),
                  ],
                ),
              ),
            ),
      floatingActionButton: selected != 7
          ? FloatingActionButton.extended(
              onPressed: working ? null : addExpense,
              icon: const Icon(Icons.add),
              label: Text(tr('Log spend')),
            )
          : null,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            NavigationRail(
              extended: true,
              selectedIndex: selected,
              onDestinationSelected: navigate,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.$2),
                    label: Text(tr(d.$1)),
                  ),
              ],
            ),
          Expanded(
            child: Column(
              children: [
                if (working) const LinearProgressIndicator(),
                if (store.warning != null)
                  MaterialBanner(
                    content: Text(store.warning!),
                    actions: [
                      TextButton(
                        onPressed: () => setState(() => selected = 7),
                        child: const Text('Backup'),
                      ),
                    ],
                  ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 40 : 16,
                          20,
                          wide ? 40 : 16,
                          100,
                        ),
                        children: [
                          Text(
                            tr(destinations[selected].$1),
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr('Private by default. Saved on this device.'),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 24),
                          sectionTabs(),
                          const SizedBox(height: 20),
                          ...sectionContent(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> today() {
    final p = planner;
    return [
      commandBar(),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CLEAN TAKE TODAY',
              style: TextStyle(
                fontFamily: 'HeistDisplay',
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              money(p.leftToday),
              style: Theme.of(
                context,
              ).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              '${p.period.days} days to cover · ${money(p.reserved)} reserved for upcoming bills and debt minimums',
            ),
            const SizedBox(height: 8),
            Text(
              'Daily limit ${money(p.dailyLimit)} · Spent today ${money(p.spentToday)}',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: addExpense,
              icon: const Icon(Icons.add),
              label: Text(tr('Log an expense')),
            ),
          ],
        ),
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      Wrap(
        spacing: 16,
        children: [
          stat(
            'Period balance',
            money(p.balance),
            subtitle: '${p.period.start} to ${p.period.end}',
          ),
          stat('Income / month', money(p.income)),
          stat('Spent this period', money(p.spent)),
        ],
      ),
      if (p.income == 0)
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set your income or opening cash to calculate your daily limit.',
              ),
              TextButton(
                onPressed: () => setState(() => selected = 2),
                child: const Text('Set up budget'),
              ),
            ],
          ),
        ),
      label('Upcoming bills'),
      if (p.dueBills.isEmpty)
        empty('No scheduled bills before the next period.'),
      for (final bill in p.dueBills.take(12))
        box(
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(bill.item['name'].toString()),
            subtitle: Text(bill.date),
            trailing: Text(money(bill.item['amount'])),
          ),
        ),
      label('Recent spending'),
      ...expenseTiles(p.expenses.reversed.take(5).toList()),
    ];
  }

  List<Field> get expenseFields => [
    const Field('amount', 'Amount', numeric: true),
    Field('categoryId', 'Category', choices: categoryChoices),
    const Field('date', 'Date', date: true),
    const Field('note', 'Note', required: false),
  ];
  Future<void> addExpense() =>
      edit('budget.expenses', 'Log spend', expenseFields);
  List<Widget> expenseTiles(List<Json> entries) => entries.isEmpty
      ? [empty('No spending recorded.')]
      : [
          for (final e in entries)
            box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e['note']?.toString().isNotEmpty == true
                              ? e['note'].toString()
                              : planner.categoryName(e['categoryId']),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(money(e['amount'])),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${e['date']} · ${planner.categoryName(e['categoryId'])}',
                  ),
                  Wrap(
                    children: [
                      if (e['debtPay'] == null &&
                          e['roundup'] == null &&
                          e['splitId'] == null &&
                          e['groupExp'] == null &&
                          e['recurringId'] == null)
                        TextButton(
                          onPressed: () => edit(
                            'budget.expenses',
                            'Edit spend',
                            expenseFields,
                            row: e,
                          ),
                          child: Text(tr('Edit')),
                        ),
                      if (e['debtPay'] == null &&
                          e['roundup'] == null &&
                          e['splitId'] == null &&
                          e['groupExp'] == null &&
                          e['recurringId'] == null)
                        TextButton(
                          onPressed: () => delete('budget.expenses', e),
                          child: Text(tr('Delete')),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Linked record · retained from your original app',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ];
  List<Widget> spend() {
    final entries =
        planner.expenses
            .where(
              (e) =>
                  '${e['note']} ${e['date']} ${planner.categoryName(e['categoryId'])}'
                      .toLowerCase()
                      .contains(search.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    return [
      TextField(
        decoration: const InputDecoration(
          labelText: 'Search spending',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (value) => setState(() => search = value),
      ),
      const SizedBox(height: 16),
      ...expenseTiles(entries),
    ];
  }

  List<Widget> budget() => [
    box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monthly income ${money(planner.income)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Use the monthly budget override for an allowance. Imported paycheck and deduction details remain in your backup.',
          ),
          TextButton(
            onPressed: editIncome,
            child: const Text('Edit allowance / income'),
          ),
        ],
      ),
    ),
    Wrap(
      spacing: 16,
      children: [
        stat(
          'Planned',
          money(
            planner.categories.fold<double>(
              0,
              (v, c) => v + number(c['planned']),
            ),
          ),
        ),
        stat(
          'Unassigned',
          money(
            planner.income -
                planner.categories.fold<double>(
                  0,
                  (v, c) => v + number(c['planned']),
                ),
          ),
        ),
      ],
    ),
    collection(
      'budget.categories',
      'Categories',
      const [
        Field('name', 'Name'),
        Field(
          'type',
          'Type',
          choices: {'needs': 'Needs', 'wants': 'Wants', 'savings': 'Savings'},
        ),
        Field('planned', 'Monthly plan', numeric: true),
      ],
      amountKey: 'planned',
      canDelete: false,
      detail: (c) =>
          'Spent ${money(planner.actual(c['id']))} · Left ${money(number(c['planned']) - planner.actual(c['id']))}',
    ),
    collection(
      'recurring',
      'Recurring bills',
      [
        const Field('name', 'Name'),
        const Field('amount', 'Amount', numeric: true),
        Field('categoryId', 'Category', choices: categoryChoices),
        const Field(
          'freq',
          'Frequency',
          choices: {
            'weekly': 'Weekly',
            'monthly': 'Monthly',
            'yearly': 'Yearly',
          },
        ),
        const Field('start', 'First due date', date: true),
      ],
      amountKey: 'amount',
      detail: (r) =>
          '${r['freq']} · From ${r['start']} · ${r['active'] == false ? 'Paused' : 'Active'}',
      actions: (r) => [
        TextButton(
          onPressed: () => act(
            () =>
                store.put('recurring', {...r, 'active': r['active'] == false}),
          ),
          child: Text(r['active'] == false ? 'Resume' : 'Pause'),
        ),
        TextButton(
          onPressed: () => postBill(r),
          child: const Text('Record payment'),
        ),
      ],
    ),
    collection(
      'subscriptions',
      'Subscriptions',
      const [
        Field('name', 'Service'),
        Field('amount', 'Price', numeric: true),
        Field(
          'cycle',
          'Billing',
          choices: {'monthly': 'Monthly', 'yearly': 'Yearly'},
        ),
        Field('since', 'Since', date: true),
      ],
      amountKey: 'amount',
      detail: (r) =>
          '${r['cycle']} · Add a recurring bill to reserve this payment in your daily limit.',
    ),
    collection(
      'yearlyBills',
      'Annual bills',
      const [
        Field('name', 'Name'),
        Field('amount', 'Amount', numeric: true),
        Field('due', 'Next due date', date: true),
      ],
      amountKey: 'amount',
      detail: (r) => 'Due ${r['due']}',
    ),
  ];
  Future<void> editIncome() async {
    final next = await editRecord(
      context,
      'Monthly money plan',
      const [
        Field('monthly', 'Monthly allowance / income', numeric: true),
        Field('next', 'Next allowance date', date: true, required: false),
        Field('cash', 'Opening cash (used if income is zero)', numeric: true),
      ],
      record: {
        'monthly': planner.income,
        'next': state['income']['nextPayDate'] ?? '',
        'cash': state['settings']['cashOnHand'] ?? 0,
      },
    );
    if (next != null)
      await act(
        () => store.mutate((s) {
          s['budget']['incomeOverride'] = next['monthly'];
          s['income']['nextPayDate'] = next['next'];
          s['income']['freq'] = 'monthly';
          s['income']['configured'] = true;
          s['student']['allowance'] = next['monthly'];
          s['settings']['cashOnHand'] = next['cash'];
        }),
      );
  }

  Future<void> postBill(Json r) async {
    final paid = await editRecord(
      context,
      'Record bill payment',
      [
        const Field('amount', 'Amount', numeric: true),
        const Field('date', 'Payment date', date: true),
        Field('categoryId', 'Category', choices: categoryChoices),
      ],
      record: {
        'amount': r['amount'],
        'date': isoDate(DateTime.now()),
        'categoryId': r['categoryId'],
      },
    );
    if (paid == null) return;
    final existing = planner.expenses.any(
      (e) => e['recurringId'] == r['id'] && e['date'] == paid['date'],
    );
    if (existing) {
      message('This bill already has a payment on that date.');
      return;
    }
    await act(
      () => store.mutate((s) {
        (s['budget']['expenses'] as List).add({
          ...paid,
          'id': newId(),
          'note': r['name'],
          'recurringId': r['id'],
        });
        for (final item in s['recurring'] as List) {
          if (item['id'] == r['id']) item['lastPosted'] = paid['date'];
        }
      }),
    );
  }

  List<Widget> split() => [
    box(
      Wrap(
        spacing: 12,
        children: [
          FilledButton(
            onPressed: splitLocalBill,
            child: const Text('Split a bill'),
          ),
          OutlinedButton(
            onPressed: () => context.go('/split/groups'),
            child: const Text('Live groups'),
          ),
        ],
      ),
    ),
    collection(
      'wallet.ious',
      'IOUs',
      const [
        Field('person', 'Person'),
        Field(
          'dir',
          'Direction',
          choices: {'owed': 'They owe me', 'owe': 'I owe them'},
        ),
        Field('amount', 'Amount', numeric: true),
        Field('date', 'Date', date: true),
        Field('due', 'Due date', date: true, required: false),
        Field('note', 'Note', required: false),
      ],
      nameKey: 'person',
      amountKey: 'amount',
      detail: (r) =>
          '${r['dir'] == 'owe' ? 'I owe them' : 'They owe me'} · ${r['settled'] == true ? 'Settled' : 'Open'}',
      actions: (r) => [
        TextButton(
          onPressed: () => act(
            () => store.put('wallet.ious', {
              ...r,
              'settled': r['settled'] != true,
              'settledAt': r['settled'] != true ? isoDate(DateTime.now()) : '',
            }),
          ),
          child: Text(r['settled'] == true ? 'Reopen' : 'Mark settled'),
        ),
        if (r['settled'] != true)
          TextButton(
            onPressed: () => upiSettlement(r),
            child: const Text('UPI / QR'),
          ),
      ],
    ),
    collection(
      'split.buckets',
      'Paycheck buckets',
      const [
        Field('name', 'Name'),
        Field(
          'role',
          'Role',
          choices: {
            'bills': 'Bills',
            'debt': 'Debt',
            'goals': 'Goals',
            'gifts': 'Gifts',
            'spending': 'Spending',
            'custom': 'Custom',
          },
        ),
        Field(
          'mode',
          'Allocation',
          choices: {'percent': 'Percent', 'amount': 'Fixed amount'},
        ),
        Field('value', 'Value', numeric: true),
      ],
      detail: (r) => r['mode'] == 'percent'
          ? '${r['value']}% of each paycheck'
          : '${money(r['value'])} per paycheck',
    ),
  ];

  List<Widget> goals() => [
    collection(
      'goals',
      'Savings goals',
      const [
        Field('name', 'Goal'),
        Field('target', 'Target', numeric: true),
        Field('saved', 'Saved so far', numeric: true),
        Field('deadline', 'Deadline', date: true, required: false),
        Field('rate', 'Annual interest %', numeric: true, max: 100),
      ],
      amountKey: 'target',
      canDelete: false,
      detail: (g) =>
          '${money(g['saved'])} saved · ${number(g['target']) > 0 ? (100 * number(g['saved']) / number(g['target'])).toStringAsFixed(0) : 0}% · Deadline ${g['deadline']}',
      actions: (g) => [
        TextButton(
          onPressed: () => contribute(g),
          child: const Text('Add savings'),
        ),
      ],
    ),
    collection(
      'gifts',
      'Gifts',
      const [
        Field('name', 'Recipient'),
        Field('occasion', 'Occasion'),
        Field('date', 'Date', date: true),
        Field('budget', 'Budget', numeric: true),
        Field('idea', 'Gift idea', required: false),
        Field(
          'status',
          'Status',
          choices: {
            'Idea': 'Idea',
            'Planned': 'Planned',
            'Bought': 'Bought',
            'Given': 'Given',
          },
        ),
      ],
      amountKey: 'budget',
      detail: (r) => '${r['occasion']} · ${r['date']} · ${r['status']}',
    ),
    collection(
      'wishlist',
      'Wishlist',
      const [
        Field('name', 'Item'),
        Field('price', 'Price', numeric: true),
        Field(
          'status',
          'Status',
          choices: {
            'waiting': 'Waiting',
            'bought': 'Bought',
            'skipped': 'Skipped',
          },
        ),
      ],
      amountKey: 'price',
      detail: (r) => '${r['status']}',
    ),
  ];
  Future<void> contribute(Json goal) async {
    final result = await editRecord(context, 'Add savings', const [
      Field('amount', 'Amount', numeric: true),
      Field('date', 'Date', date: true),
      Field('note', 'Note', required: false),
    ]);
    if (result == null || number(result['amount']) <= 0) return;
    await act(
      () => store.mutate((s) {
        final g = (s['goals'] as List).firstWhere((x) => x['id'] == goal['id']);
        g['saved'] = number(g['saved']) + number(result['amount']);
        g['contributions'] = [...rows(g['contributions']), result];
        // Savings transfers count as a cash outflow exactly once.
        final categories = s['budget']['categories'] as List;
        var savings = categories
            .where((c) => c['type'] == 'savings')
            .firstOrNull;
        if (savings == null) {
          savings = {
            'id': newId(),
            'name': 'Savings',
            'type': 'savings',
            'planned': 0,
          };
          categories.add(savings);
        }
        (s['budget']['expenses'] as List).add({
          'id': newId(),
          'amount': result['amount'],
          'date': result['date'],
          'categoryId': savings['id'],
          'note': 'Savings: ${g['name']}',
          'roundup': {
            'goalId': g['id'],
            'cid': result['id'],
            'amount': result['amount'],
          },
        });
      }),
    );
  }

  List<Widget> debt() => [
    Wrap(
      spacing: 16,
      children: [
        stat(
          'Total debt',
          money(
            rows(
              state['debts'],
            ).fold<double>(0, (v, d) => v + number(d['balance'])),
          ),
        ),
        stat(
          'Minimums / month',
          money(
            rows(
              state['debts'],
            ).fold<double>(0, (v, d) => v + number(d['minPayment'])),
          ),
        ),
      ],
    ),
    collection(
      'debts',
      'Debts',
      const [
        Field('name', 'Lender / debt'),
        Field('balance', 'Balance', numeric: true),
        Field('rate', 'Annual interest %', numeric: true, max: 100),
        Field('minPayment', 'Monthly minimum', numeric: true),
      ],
      amountKey: 'balance',
      canDelete: false,
      detail: (d) {
        final balance = number(d['balance']),
            rate = number(d['rate']) / 1200,
            payment = number(d['minPayment']);
        final months = payment <= 0 || payment <= balance * rate
            ? null
            : rate == 0
            ? balance / payment
            : -math.log(1 - balance * rate / payment) / math.log(1 + rate);
        return '${d['rate']}% APR · ${money(payment)} minimum · ${balance == 0
            ? 'Paid off'
            : months == null
            ? 'Minimum does not cover interest'
            : 'About ${months.ceil()} months at this payment'}';
      },
      actions: (d) => [
        TextButton(
          onPressed: number(d['balance']) > 0 ? () => payDebt(d) : null,
          child: const Text('Record payment'),
        ),
      ],
    ),
  ];
  Future<void> payDebt(Json debt) async {
    final p = await editRecord(context, 'Record debt payment', [
      Field(
        'amount',
        'Principal paid (max ${money(debt['balance'])})',
        numeric: true,
        max: number(debt['balance']),
      ),
      const Field('date', 'Date', date: true),
      Field('categoryId', 'Budget category', choices: categoryChoices),
    ]);
    if (p == null || number(p['amount']) <= 0) return;
    await act(
      () => store.mutate((s) {
        final d = (s['debts'] as List).firstWhere((x) => x['id'] == debt['id']);
        if (number(p['amount']) > number(d['balance']))
          throw const FormatException('Payment exceeds remaining debt.');
        d['startBalance'] ??= d['balance'];
        d['balance'] =
            ((number(d['balance']) - number(p['amount'])) * 100).round() / 100;
        d['payments'] = [
          ...rows(d['payments']),
          {'id': p['id'], 'date': p['date'], 'amount': p['amount']},
        ];
        (s['budget']['expenses'] as List).add({
          ...p,
          'id': newId(),
          'note': 'Debt: ${d['name']}',
          'debtPay': {'debtId': d['id'], 'pid': p['id'], 'amount': p['amount']},
        });
      }),
    );
  }

  List<Widget> wallet() => [
    stat(
      'Cash ledger balance',
      money(
        rows(state['wallet']['cash']).fold<double>(
          0,
          (v, r) => v + (r['type'] == 'out' ? -1 : 1) * number(r['amount']),
        ),
      ),
      subtitle: 'Separate cash ledger; does not change spending automatically.',
    ),
    box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Bank / UPI balance')),
          TextButton(
            onPressed: setBank,
            child: const Text('Update balance used by daily limit'),
          ),
        ],
      ),
    ),
    collection(
      'wallet.cash',
      'Cash entries',
      const [
        Field('note', 'Description'),
        Field('amount', 'Amount', numeric: true),
        Field(
          'type',
          'Direction',
          choices: {'in': 'Cash in', 'out': 'Cash out'},
        ),
        Field('date', 'Date', date: true),
      ],
      nameKey: 'note',
      amountKey: 'amount',
      detail: (r) => '${r['type']} · ${r['date']}',
    ),
    collection(
      'incomeLog',
      'Income received',
      const [
        Field('note', 'Source'),
        Field('amount', 'Amount', numeric: true),
        Field('date', 'Date', date: true),
      ],
      nameKey: 'note',
      amountKey: 'amount',
      detail: (r) =>
          '${r['date']} · Adjusts a bank balance if one is set; monthly allowance is configured in Budget.',
    ),
    collection(
      'wallet.deadlines',
      'Deadlines',
      const [Field('title', 'Title'), Field('date', 'Date', date: true)],
      nameKey: 'title',
      detail: (r) => '${r['date']}',
    ),
    collection(
      'wallet.transport',
      'Transport log',
      const [
        Field(
          'mode',
          'Mode',
          choices: {
            'bus': 'Bus',
            'metro': 'Metro',
            'train': 'Train',
            'auto': 'Auto',
            'cab': 'Cab',
            'other': 'Other',
          },
        ),
        Field('amount', 'Cost', numeric: true),
        Field('date', 'Date', date: true),
        Field('note', 'Note', required: false),
      ],
      nameKey: 'mode',
      amountKey: 'amount',
      detail: (r) =>
          '${r['date']} · Separate log; use Log spend to count new travel in your budget.',
    ),
    collection(
      'wallet.taxes',
      'Tax records',
      const [
        Field('type', 'Tax type'),
        Field('amount', 'Amount', numeric: true),
        Field('date', 'Date', date: true),
        Field('note', 'Note', required: false),
      ],
      nameKey: 'type',
      amountKey: 'amount',
      detail: (r) => '${r['date']}',
    ),
    collection(
      'payslips',
      'Payslips',
      const [
        Field('employer', 'Employer'),
        Field('month', 'Month (YYYY-MM)'),
        Field('gross', 'Gross', numeric: true),
        Field('net', 'Net', numeric: true),
        Field('tax', 'Tax', numeric: true),
        Field('pf', 'PF', numeric: true),
      ],
      nameKey: 'employer',
      amountKey: 'net',
      detail: (r) => '${r['month']} · Gross ${money(r['gross'])}',
    ),
  ];
  Future<void> setBank() async {
    final r = await editRecord(context, 'Set bank balance', const [
      Field('amount', 'Current balance', numeric: true),
    ]);
    if (r == null) return;
    await act(
      () => store.mutate((s) {
        s['settings']['bank'] = {
          'amount': r['amount'],
          'use': true,
          'asOf': isoDate(DateTime.now()),
          'spentBase': rows(
            s['budget']['expenses'],
          ).fold<double>(0, (v, e) => v + number(e['amount'])),
          'incomeBase': rows(
            s['incomeLog'],
          ).fold<double>(0, (v, e) => v + number(e['amount'])),
        };
      }),
    );
  }

  Widget backupPanel() => box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Offline storage'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'SQLite revision ${store.revision}. Up to 20 local revisions and 10 Hive recovery copies.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Both stores are on this device. Export a JSON file to protect against device loss, app removal, or cleared browser storage.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: working ? null : exportBackup,
              icon: const Icon(Icons.download),
              label: Text(tr('Export JSON')),
            ),
            OutlinedButton.icon(
              onPressed: working ? null : importBackup,
              icon: const Icon(Icons.upload),
              label: Text(tr('Import HEIST backup')),
            ),
            OutlinedButton(
              onPressed: working ? null : recoveryHistory,
              child: Text(tr('Recovery history')),
            ),
          ],
        ),
      ],
    ),
  );

  Widget offlineHelpPanel() => box(
    const Text(
      'Works offline: spending, budgets, bill planning, local IOUs, goals, debt payments, loan calculations, statement import, receipt OCR, and backups.\n\nInternet is needed for sign-in, joining groups, receiving shared updates, and cloud AI. Changes to an already joined group can be queued offline.\n\nWeb offline launch requires one complete online load. Native installed apps launch without internet. Export backups to a separate device or location.',
    ),
  );

  List<Widget> settings() => settingsPage();

  Future<void> exportBackup() => act(() async {
    final saved = await saveBackupFile(
      'heist-backup-${isoDate(DateTime.now())}.json',
      await BackupCodec.encode(store.state),
    );
    if (saved)
      message('Backup export opened. Keep a copy outside this device.');
  });
  Future<void> importBackup() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'HEIST JSON backup',
            extensions: ['json'],
            mimeTypes: ['application/json'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 20 * 1024 * 1024)
        throw const FormatException('Backup exceeds 20 MB.');
      final text = await file.readAsString();
      final next = await BackupCodec.decode(text);
      if (!mounted) return;
      final count = rows(next['budget']['expenses']).length;
      if (!await confirm(
        context,
        'Replace current planner?',
        'Import ${file.name} with $count expenses? The current planner remains in local recovery history. Export a separate backup first for long-term safety.',
      ))
        return;
      await act(() async {
        await store.pauseSynchronization(true);
        await store.importBackup(jsonEncode(next));
      });
    } catch (e) {
      message('Import failed: $e');
    }
  }

  Future<void> recoveryHistory() async {
    final revisions = await store.history();
    if (!mounted) return;
    final id = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore a local revision'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: ListView(
            children: [
              for (final r in revisions)
                ListTile(
                  title: Text('Revision ${r['revision']}'),
                  subtitle: Text(r['created_at'].toString()),
                  trailing: const Icon(Icons.restore),
                  onTap: () => Navigator.pop(context, r['revision'] as int),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Cancel')),
          ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    if (await confirm(
      context,
      'Restore revision $id?',
      'This restores the full planner. A new revision records the restore.',
    ))
      await act(() async {
        await store.pauseSynchronization(true);
        await store.restore(id);
      });
  }

  List<Widget> accountPanel() {
    final sync = widget.sync!;
    return [
      box(
        ListenableBuilder(
          listenable: sync,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account & synchronization',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                sync.ready
                    ? 'Signed in · ${sync.pending} pending changes'
                    : 'Sign in to synchronize your encrypted planner.',
              ),
              if (sync.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(sync.error!),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (sync.backend.session == null)
                    FilledButton(
                      onPressed: accountSignIn,
                      child: const Text('Sign in'),
                    )
                  else if (!sync.ready)
                    FilledButton(
                      onPressed: unlockAccount,
                      child: const Text('Unlock vault'),
                    ),
                  if (sync.ready)
                    OutlinedButton(
                      onPressed: () => sync.synchronize(manual: true),
                      child: const Text('Sync now'),
                    ),
                  if (sync.ready)
                    OutlinedButton(
                      onPressed: () => act(() async {
                        await store.pauseSynchronization(false);
                        await sync.synchronize(manual: true);
                      }),
                      child: const Text('Resume synchronization'),
                    ),
                  if (sync.ready)
                    TextButton(
                      onPressed: rotateVaultKeys,
                      child: const Text('Change passphrase / recovery key'),
                    ),
                  if (sync.backend.session != null)
                    TextButton(
                      onPressed: accountSignIn,
                      child: const Text('Sign in again'),
                    ),
                  if (sync.ready)
                    TextButton(
                      onPressed: deleteCloudAccount,
                      child: const Text('Delete cloud account'),
                    ),
                  if (sync.backend.session != null)
                    TextButton(
                      onPressed: () async {
                        if (!await confirm(
                          context,
                          'Sign out?',
                          'Pending writes remain on this device and resume only when the same account signs in again.',
                        ))
                          return;
                        await act(() async {
                          await sync.backend.signOut();
                          await store.unbindAccount();
                        });
                      },
                      child: const Text('Sign out'),
                    ),
                  TextButton(
                    onPressed: resolveSyncConflict,
                    child: const Text('Resolve conflict'),
                  ),
                  TextButton(
                    onPressed: pendingChanges,
                    child: const Text('Pending changes & failures'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Future<void> pendingChanges() async {
    final items = await store.pendingSummary();
    if (!mounted) return;
    final retry = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pending changes & failures'),
        content: SizedBox(
          width: 520,
          height: 320,
          child: ListView(
            children: [
              if (items.isEmpty)
                const Text(
                  'No queued changes. Local-only data is saved on this device.',
                ),
              for (final item in items)
                ListTile(
                  title: Text(
                    '${item['kind']} · revision ${item['revision']} · ${item['status']}',
                  ),
                  subtitle: Text(
                    'Attempts: ${item['attempts']}${item['error'] == null ? '' : '\n${item['error']}'}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr('Close')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Retry failures'),
          ),
        ],
      ),
    );
    if (retry == true)
      await act(() async {
        await store.retryFailed();
        await widget.sync?.synchronize(manual: true);
        await widget.groups?.synchronize();
      });
  }

  Future<void> accountSignIn() async {
    final backend = widget.sync!.backend;
    if (!backend.configured) {
      message('Backend is not configured for this build.');
      return;
    }
    final currentEmail = backend.session?['user']?['email']?.toString();
    final login = await editRecord(
      context,
      'Sign in',
      const [Field('email', 'Email')],
      record: {'email': currentEmail ?? ''},
    );
    if (login == null || !mounted) return;
    if (currentEmail != null &&
        currentEmail.toLowerCase() !=
            login['email'].toString().trim().toLowerCase()) {
      message('Sign out before using a different email account.');
      return;
    }
    if (!await confirm(
      context,
      'Email sign-in link',
      'Send a sign-in email? New users create an account under the existing HEIST Terms of Use and Privacy Policy. Continue only if you agree.',
    ))
      return;
    await act(() => backend.sendCode(login['email'] as String));
    if (!mounted) return;
    final code = await editRecord(
      context,
      'Code from your sign-in email',
      const [Field('code', 'Email code', obscure: true)],
    );
    if (code == null) return;
    await act(
      () =>
          backend.verifyCode(login['email'] as String, code['code'] as String),
    );
    if (backend.session != null && mounted) await unlockAccount();
  }

  Future<void> unlockAccount() async {
    final sync = widget.sync!;
    await act(
      () => sync.selectAccount(() async {
        final row = await sync.backend.vault();
        if (!mounted) return;
        final pass = await editRecord(
          context,
          row == null ? 'Create vault passphrase' : 'Unlock vault',
          [
            if (row != null)
              const Field(
                'method',
                'Unlock with',
                choices: {'pass': 'Passphrase', 'recovery': 'Recovery key'},
              ),
            const Field('pass', 'Passphrase or recovery key', obscure: true),
            if (row == null)
              const Field('confirm', 'Repeat passphrase', obscure: true),
          ],
        );
        if (pass == null) return;
        if (row == null) {
          if (pass['pass'] != pass['confirm'])
            throw const FormatException('Passphrases do not match.');
          if ((pass['pass'] as String).length < 8)
            throw const FormatException('Use at least 8 characters.');
          final keys = await sync.crypto.create(pass['pass'] as String);
          final result = await sync.backend.request(
            '/rest/v1/vaults',
            method: 'POST',
            prefer: 'return=representation',
            body: {
              'user_id': sync.backend.uid,
              ...keys.fields,
              'data': await sync.crypto.lock(store.state, keys.key),
              'version': 1,
              'device': 'Flutter',
            },
          );
          await store.bindAccount(
            sync.backend.uid!,
            number(rows(result).first['version']).toInt(),
          );
          sync.backend.dataKey = keys.key;
          await sync.backend.persist();
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Save your recovery key'),
              content: SelectableText(keys.recovery),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('I saved the key'),
                ),
              ],
            ),
          );
        } else {
          final key = pass['method'] == 'recovery'
              ? await sync.crypto.openRecovery(row, pass['pass'] as String)
              : await sync.crypto.openPass(row, pass['pass'] as String);
          final remote = await sync.crypto.unlock(row['data'] as String, key);
          if (!mounted) return;
          final useRemote = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Choose your planner'),
              content: const Text(
                'Both copies will be retained locally before replacement.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Decide later'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Use this device'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Use account copy'),
                ),
              ],
            ),
          );
          if (useRemote == null) {
            sync.backend.dataKey = null;
            await sync.backend.persist();
            return;
          }
          await store.bindAccount(
            sync.backend.uid!,
            number(row['version']).toInt(),
          );
          await store.parkConflict(
            sync.backend.uid!,
            remote,
            number(row['version']).toInt(),
          );
          final conflicts = await store.conflicts(sync.backend.uid!);
          await store.resolveConflict(
            sync.backend.uid!,
            conflicts.first['id'] as String,
            useRemote: useRemote,
          );
          sync.backend.dataKey = key;
          await sync.backend.persist();
        }
      }),
    );
  }

  Future<void> resolveSyncConflict() async {
    final sync = widget.sync!;
    if (sync.backend.uid == null) return;
    final conflicts = await store.conflicts(sync.backend.uid!);
    if (conflicts.isEmpty) {
      message('No saved conflicts.');
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Choose the planner to keep'),
        content: const Text(
          'Both copies remain in recovery history. Choosing this device may overwrite the account copy on the next successful sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Decide later'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('This device'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Account copy'),
          ),
        ],
      ),
    );
    if (choice != null)
      await act(
        () => sync.resolve(conflicts.first['id'] as String, useRemote: choice),
      );
  }
}
