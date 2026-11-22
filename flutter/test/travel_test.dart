import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:heist_flutter/data/backend.dart';
import 'package:heist_flutter/data/backup_codec.dart';
import 'package:heist_flutter/data/local_store.dart';
import 'package:heist_flutter/data/travel_agent.dart';
import 'package:heist_flutter/domain/travel.dart';

void main() {
  final trip = <String, dynamic>{
    'id': 'trip1',
    'destination': 'Hyderabad',
    'origin': 'Warangal',
    'startDate': '2026-12-01',
    'days': 1,
    'travelers': 2,
    'currency': 'INR',
    'budget': 5000,
    'people': ['A', 'B'],
    'expenses': [],
  };
  test('trip validation, source links and cent-accurate shared costs', () {
    expect(travelBrief(trip)['days'], 1);
    expect(() => travelBrief({...trip, 'days': 0}), throwsFormatException);
    expect(
      () => travelBrief({...trip, 'startDate': '2026-02-31'}),
      throwsFormatException,
    );
    expect(travelUrl('javascript:alert(1)'), false);
    final balances = travelBalances({
      ...trip,
      'expenses': [
        {'amount': 10.01, 'paidBy': 'A'},
      ],
    });
    expect(balances['A'], closeTo(5, 0.001));
    expect(balances['B'], closeTo(-5, 0.001));
    expect(
      travelSpent({
        ...trip,
        'expenses': [
          {'amount': 10.01},
        ],
      }),
      10.01,
    );
    expect(
      () => travelPlan({'days': [], 'budget': []}, 1),
      throwsFormatException,
    );
  });
  test(
    'research checkpoint survives restart; retry skips search; trip survives backup',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('heist_travel_');
      Hive.init(dir.path);
      final recovery = await Hive.openBox<String>('recovery');
      final prefs = await Hive.openBox<dynamic>('prefs');
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
      );
      final store = LocalStore(db, recovery, prefs);
      await store.load();
      await store.put('travelTrips', trip);
      var researchCalls = 0, planCalls = 0;
      final backend =
          HeistBackend(
              url: 'https://test.supabase.co',
              publishableKey: 'public',
              client: MockClient((request) async {
                final body = jsonDecode(request.body);
                expect(body['trip'].containsKey('expenses'), false);
                expect(body['trip'].containsKey('people'), false);
                if (body['stage'] == 'research') {
                  researchCalls++;
                  return http.Response(
                    jsonEncode({
                      'summary': 'Research',
                      'sources': [
                        {'title': 'Official', 'url': 'https://tourism.gov.in'},
                      ],
                    }),
                    200,
                  );
                }
                planCalls++;
                if (planCalls == 1)
                  return http.Response('{"error":"Provider unavailable"}', 503);
                expect(body['research']['summary'], 'Research');
                return http.Response(
                  jsonEncode({
                    'plan': {
                      'summary': 'Visit',
                      'days': [
                        {
                          'day': 1,
                          'stops': [
                            {'name': 'Museum', 'cost': 100},
                          ],
                        },
                      ],
                      'budget': [
                        {'category': 'Food', 'amount': 500},
                      ],
                    },
                  }),
                  200,
                );
              }),
            )
            ..session = {
              'access_token': 'test',
              'expires_at':
                  DateTime.now().millisecondsSinceEpoch / 1000 + 10000,
              'user': {'id': 'u'},
            };
      await expectLater(
        TravelAgent(store, backend).generate('trip1'),
        throwsA(isA<BackendFailure>()),
      );
      final reopened = LocalStore(db, recovery, prefs);
      await reopened.load();
      expect(reopened.collection('travelTrips').single['status'], 'researched');
      await TravelAgent(reopened, backend).generate('trip1');
      expect(researchCalls, 1);
      expect(planCalls, 2);
      final backup = await BackupCodec.decode(await BackupCodec.encode(reopened.state));
      await reopened.importBackup(jsonEncode(backup));
      expect(backup['travelTrips'][0]['status'], 'ready');
      expect(
        backup['travelTrips'][0]['plan']['days'][0]['stops'][0]['name'],
        'Museum',
      );
      store.dispose();
      reopened.dispose();
      await db.close();
      await Hive.close();
    },
  );
}
