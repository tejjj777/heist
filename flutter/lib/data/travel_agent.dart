import 'backend.dart';
import 'local_store.dart';
import '../domain/planner.dart';
import '../domain/travel.dart';

class TravelAgent {
  final LocalStore store;
  final HeistBackend backend;
  TravelAgent(this.store, this.backend);

  Future<void> generate(String id, {void Function(String)? progress}) async {
    Json current() =>
        store.collection('travelTrips').firstWhere((t) => t['id'] == id);
    var trip = current();
    travelBrief(trip);
    final brief = <String, dynamic>{
      for (final key in [
        'destination',
        'origin',
        'startDate',
        'days',
        'travelers',
        'budget',
        'currency',
        'interests',
        'pace',
      ])
        key: trip[key],
    };
    try {
      if (trip['research'] is! Map) {
        progress?.call('Searching travel sources…');
        final result = await backend.request(
          '/functions/v1/travel',
          method: 'POST',
          body: {'stage': 'research', 'trip': brief},
          timeout: const Duration(seconds: 65),
        );
        if (result is! Map ||
            result['summary'] is! String ||
            rows(result['sources']).isEmpty) {
          throw const FormatException('Research returned no sources. Retry.');
        }
        trip = {
          ...current(),
          'research': result,
          'status': 'researched',
          'error': null,
        };
        await store.put(
          'travelTrips',
          trip,
        ); // Durable checkpoint before the next AI request.
      }
      progress?.call('Building your day-by-day itinerary…');
      final result = await backend.request(
        '/functions/v1/travel',
        method: 'POST',
        body: {'stage': 'plan', 'trip': brief, 'research': trip['research']},
        timeout: const Duration(seconds: 65),
      );
      final plan = travelPlan(
        result is Map ? result['plan'] : null,
        trip['days'] as int,
      );
      await store.put('travelTrips', {
        ...current(),
        'plan': plan,
        'status': 'ready',
        'error': null,
      });
    } catch (e) {
      await store.put('travelTrips', {...current(), 'error': e.toString()});
      rethrow;
    }
  }
}
