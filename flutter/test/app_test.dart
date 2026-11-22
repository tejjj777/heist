import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:heist_flutter/data/local_store.dart';
import 'package:heist_flutter/ui/app.dart';
import 'package:go_router/go_router.dart';
import 'package:heist_flutter/domain/planner.dart';
import 'package:heist_flutter/ui/travel_section.dart';

void main() {
  late Database db;
  late LocalStore store;
  setUp(() async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('heist_widget_');
    Hive.init(directory.path);
    final recovery = await Hive.openBox<String>('widget_recovery');
    final prefs = await Hive.openBox<dynamic>('widget_preferences');
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    store = LocalStore(db, recovery, prefs);
    await store.load();
    await store.setPreference('tutorial.v1', true);
  });
  tearDown(() async {
    store.dispose();
    await db.close();
    await Hive.close();
  });

  testWidgets('saved travel panels render at 360 pixels without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => store.put('travelTrips', {
        'id': 't',
        'destination': 'Hyderabad',
        'origin': 'Warangal',
        'startDate': '2026-12-01',
        'days': 1,
        'travelers': 2,
        'budget': 5000,
        'currency': 'INR',
        'people': ['A', 'B'],
        'expenses': [],
        'plan': {
          'summary': 'A day in Hyderabad',
          'days': [
            {
              'day': 1,
              'title': 'Old city',
              'stops': [
                {
                  'name': 'Charminar',
                  'time': '09:00',
                  'notes': 'Check visiting hours',
                  'cost': 100,
                },
              ],
            },
          ],
          'budget': [
            {'category': 'Food', 'amount': 500},
          ],
          'hotels': [],
          'warnings': [],
        },
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TravelSection(store: store)),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hyderabad · 2026-12-01').last);
    await tester.pumpAndSettle();
    for (final name in ['Itinerary', 'Stays', 'Budget', 'Group', 'Sources']) {
      final chip = find.widgetWithText(ChoiceChip, name);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
    }
  });

  testWidgets('all nine desktop sections render without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(HeistApp(store: store));
    for (final name in [
      'Today',
      'Spend',
      'Budget',
      'Split',
      'Goals',
      'Debt',
      'Wallet',
      'Backup & settings',
      'Travel Agent',
    ]) {
      final nav = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text(name),
      );
      await tester.tap(nav);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      final tabLabels = tester
          .widgetList<ChoiceChip>(
            find.descendant(
              of: find.byKey(const Key('section-tabs')),
              matching: find.byType(ChoiceChip),
            ),
          )
          .map((chip) => (chip.label as Text).data!)
          .toList();
      for (final label in tabLabels) {
        final target = find.descendant(
          of: find.byKey(const Key('section-tabs')),
          matching: find.widgetWithText(ChoiceChip, label),
        );
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$name / $label');
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('background data updates redraw the current screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(HeistApp(store: store));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => store.mutate((s) => s['budget']['incomeOverride'] = 4321.56),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('4,321.56'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone layout opens navigation and expense form', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(HeistApp(store: store));
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Amount'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  Future<void> routeTo(WidgetTester tester, String path) async {
    GoRouter.of(tester.element(find.byType(PlannerShell))).go(path);
    await tester.pumpAndSettle();
  }

  testWidgets('settings tabs have distinct interfaces', (tester) async {
    await tester.pumpWidget(HeistApp(store: store));
    await tester.pumpAndSettle();
    await routeTo(tester, '/settings/general');
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Export JSON'), findsNothing);
    await routeTo(tester, '/settings/money');
    expect(find.text('Money preferences'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
    await routeTo(tester, '/settings/data');
    expect(find.text('Export JSON'), findsOneWidget);
    expect(find.text('Replay tutorial'), findsNothing);
    await routeTo(tester, '/settings/help');
    expect(find.text('Replay tutorial'), findsOneWidget);
    expect(find.text('Export JSON'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('wallet tabs and combined search date direction filters work', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.runAsync(
      () => store.put('wallet.cash', {
        'id': 'new',
        'note': 'Bus cash',
        'amount': 25,
        'type': 'out',
        'date': isoDate(now),
      }),
    );
    await tester.runAsync(
      () => store.put('wallet.cash', {
        'id': 'old',
        'note': 'Old deposit',
        'amount': 100,
        'type': 'in',
        'date': isoDate(now.subtract(const Duration(days: 60))),
      }),
    );
    await tester.pumpWidget(HeistApp(store: store));
    await tester.pumpAndSettle();
    await routeTo(tester, '/wallet/cash');
    final cash = find.text('Bus cash');
    // Scroll to force lazy record widgets to be built.
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(cash, findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Last 7 days'));
    await tester.enterText(find.byKey(const Key('wallet-search')), 'bus');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('Old deposit'), findsNothing);
    expect(find.text('Bus cash'), findsOneWidget);
    await routeTo(tester, '/wallet/transport');
    expect(find.text('Cash entries'), findsNothing);
    await routeTo(tester, '/wallet/subs');
    expect(find.text('Transport log'), findsNothing);
    await routeTo(tester, '/wallet/ious');
    expect(find.text('Cash ledger balance'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('first-use guide persists dismissal and can replay', (
    tester,
  ) async {
    await tester.runAsync(() => store.setPreference('tutorial.v1', false));
    await tester.pumpWidget(HeistApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Skip'));
      await store.preferencesSaved;
    });
    await tester.pumpAndSettle();
    expect(store.preferences.get('tutorial.v1'), true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(HeistApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await routeTo(tester, '/settings/help');
    await tester.tap(find.text('Replay tutorial'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Skip'));
      await store.preferencesSaved;
    });
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'phone supports amount privacy language changes and scanner choices',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(HeistApp(store: store));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Hide amounts'));
        await store.preferencesSaved;
      });
      await tester.pumpAndSettle();
      expect(store.hideAmounts, true);
      expect(find.text('••••'), findsWidgets);
      await tester.tap(find.byTooltip('Scan receipt'));
      await tester.pumpAndSettle();
      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Choose image'), findsOneWidget);
      Navigator.of(tester.element(find.text('Take photo'))).pop();
      await tester.pumpAndSettle();
      for (final lang in ['te', 'hi']) {
        await tester.runAsync(() => store.setPreference('language', lang));
        await tester.pumpAndSettle();
        await routeTo(tester, '/settings/general');
        expect(
          find.text(lang == 'te' ? 'భాష' : 'भाषा'),
          findsOneWidget,
        );
        expect(
          Localizations.localeOf(
            tester.element(find.byType(PlannerShell)),
          ).languageCode,
          lang,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
