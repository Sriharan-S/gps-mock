import 'package:flutter_test/flutter_test.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/models/mock_history_entry.dart';
import 'package:gps_mock/services/route_import_service.dart';
import 'package:gps_mock/services/route_service.dart';
import 'package:gps_mock/services/search_service.dart';

void main() {
  group('RouteService.parseOsrmResponse', () {
    test('parses a valid route', () {
      const body = '''
      {
        "code": "Ok",
        "routes": [
          {
            "geometry": {
              "coordinates": [[80.27, 13.08], [79.13, 12.94], [78.15, 11.66]],
              "type": "LineString"
            },
            "distance": 344000.5,
            "duration": 18000.0
          }
        ]
      }
      ''';

      final result = RouteService.parseOsrmResponse(body);

      expect(result.points, hasLength(3));
      // GeoJSON is [lng, lat]; LatLng is (lat, lng).
      expect(result.points.first.latitude, 13.08);
      expect(result.points.first.longitude, 80.27);
      expect(result.points.last.latitude, 11.66);
      expect(result.distanceMeters, 344000.5);
      expect(result.osrmDurationSeconds, 18000.0);
    });

    test('throws RouteException when no route exists', () {
      const body = '{"code": "NoRoute", "routes": []}';
      expect(
        () => RouteService.parseOsrmResponse(body),
        throwsA(isA<RouteException>()),
      );
    });

    test('throws RouteException when geometry is missing', () {
      const body = '''
      {"code": "Ok", "routes": [{"distance": 10, "duration": 5}]}
      ''';
      expect(
        () => RouteService.parseOsrmResponse(body),
        throwsA(isA<RouteException>()),
      );
    });
  });

  group('RouteImportService', () {
    test('parses a GPX track and sums the distance', () {
      const gpx = '''
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" creator="test">
        <metadata><name>Morning ride</name></metadata>
        <trk>
          <trkseg>
            <trkpt lat="48.2082" lon="16.3738"></trkpt>
            <trkpt lat="48.2100" lon="16.3800"></trkpt>
            <trkpt lat="48.2150" lon="16.3900"></trkpt>
          </trkseg>
        </trk>
      </gpx>
      ''';

      final route = RouteImportService.parse(gpx, sourceName: 'ride.gpx');

      expect(route.points, hasLength(3));
      expect(route.points.first.latitude, 48.2082);
      expect(route.points.first.longitude, 16.3738);
      expect(route.points.last.latitude, 48.2150);
      expect(route.distanceMeters, greaterThan(0));
      // GPX <name> wins over the file name.
      expect(route.name, 'Morning ride');
      expect(route.recordedDurationSeconds, isNull);
    });

    test('derives a recorded duration from GPX timestamps', () {
      const gpx = '''
      <gpx>
        <trk><trkseg>
          <trkpt lat="10.0" lon="20.0"><time>2023-05-01T10:00:00Z</time></trkpt>
          <trkpt lat="10.1" lon="20.1"><time>2023-05-01T10:10:00Z</time></trkpt>
        </trkseg></trk>
      </gpx>
      ''';

      final route = RouteImportService.parse(gpx);

      expect(route.points, hasLength(2));
      expect(route.recordedDurationSeconds, 600); // 10 minutes
    });

    test('falls back to route points when there is no track', () {
      const gpx = '''
      <gpx>
        <rte>
          <rtept lat="1.0" lon="2.0"/>
          <rtept lat="3.0" lon="4.0"/>
        </rte>
      </gpx>
      ''';

      final route = RouteImportService.parse(gpx);
      expect(route.points, hasLength(2));
      expect(route.points.first.latitude, 1.0);
    });

    test('parses a plain coordinate list (lat, lon per line)', () {
      const text = '''
      # a couple of points
      48.2082, 16.3738
      48.2100 16.3800
      48.2150,16.3900,320
      ''';

      final route = RouteImportService.parse(text, sourceName: 'points.txt');

      expect(route.points, hasLength(3));
      expect(route.points[1].latitude, 48.2100);
      expect(route.points[1].longitude, 16.3800);
      // Extra elevation column is ignored.
      expect(route.points[2].longitude, 16.3900);
      expect(route.name, 'points');
    });

    test('throws when fewer than two points are provided', () {
      expect(
        () => RouteImportService.parse('48.2, 16.3'),
        throwsA(isA<RouteImportException>()),
      );
    });

    test('throws on out-of-range coordinates', () {
      expect(
        () => RouteImportService.parse('91.0, 16.3\n10.0, 20.0'),
        throwsA(isA<RouteImportException>()),
      );
    });

    test('throws on unparseable coordinate lines', () {
      expect(
        () => RouteImportService.parse('hello world\n10.0, 20.0'),
        throwsA(isA<RouteImportException>()),
      );
    });

    test('throws on empty content', () {
      expect(
        () => RouteImportService.parse('   '),
        throwsA(isA<RouteImportException>()),
      );
    });
  });

  group('SearchService.parsePhotonResponse', () {
    test('parses features with names and builds descriptions', () {
      const body = '''
      {
        "features": [
          {
            "geometry": {"coordinates": [78.146, 11.664], "type": "Point"},
            "properties": {
              "name": "Salem",
              "state": "Tamil Nadu",
              "country": "India"
            }
          },
          {
            "geometry": {"coordinates": [80.27, 13.08], "type": "Point"},
            "properties": {"street": "Anna Salai", "city": "Chennai"}
          },
          {
            "geometry": {"coordinates": [0, 0], "type": "Point"},
            "properties": {}
          }
        ]
      }
      ''';

      final results = SearchService.parsePhotonResponse(body);

      expect(results, hasLength(2)); // nameless feature skipped
      expect(results[0].name, 'Salem');
      expect(results[0].description, 'Tamil Nadu, India');
      expect(results[0].location.latitude, 11.664);
      expect(results[0].location.longitude, 78.146);
      // Falls back to the street name; excludes it from the description.
      expect(results[1].name, 'Anna Salai');
      expect(results[1].description, 'Chennai');
    });

    test('returns empty list for empty feature collections', () {
      expect(SearchService.parsePhotonResponse('{"features": []}'), isEmpty);
    });
  });

  group('LocationItem', () {
    test('round-trips through JSON with its id', () {
      final item = LocationItem(
        id: 'abc',
        latitude: 1.5,
        longitude: 2.5,
        name: 'Home',
        address: 'Somewhere',
      );
      final restored = LocationItem.fromJson(item.toJson());
      expect(restored.id, 'abc');
      expect(restored.latitude, 1.5);
      expect(restored.longitude, 2.5);
      expect(restored.name, 'Home');
    });

    test('back-fills a stable id for favorites saved before ids existed', () {
      final legacy = {
        'latitude': 13.08,
        'longitude': 80.27,
        'name': 'Chennai',
        'address': 'Chennai, India',
      };
      final a = LocationItem.fromJson(legacy);
      final b = LocationItem.fromJson(legacy);
      expect(a.id, isNotEmpty);
      expect(a.id, b.id); // deterministic across loads
    });

    test('generates unique ids for new favorites', () {
      final item = LocationItem(
        latitude: 0,
        longitude: 0,
        name: 'X',
        address: 'Y',
      );
      expect(item.id, isNotEmpty);
    });
  });

  group('MockHistoryEntry', () {
    test('parses a completed route session', () {
      final entry = MockHistoryEntry.fromJson({
        'mode': 'route',
        'fromLabel': 'Chennai',
        'toLabel': 'Salem',
        'distanceMeters': 340000,
        'durationSeconds': 600,
        'startedAt': 1000000,
        'arrivedAt': 1600000,
        'endedAt': 1700000,
        'arrived': true,
      });

      expect(entry.isRoute, isTrue);
      expect(entry.isRunning, isFalse);
      expect(entry.fromLabel, 'Chennai');
      expect(entry.toLabel, 'Salem');
      expect(entry.arrived, isTrue);
      expect(entry.arrivedAt, isNotNull);
      expect(entry.duration.inMilliseconds, 700000);
    });

    test('treats a missing endedAt as a still-running session', () {
      final entry = MockHistoryEntry.fromJson({
        'mode': 'fixed',
        'label': 'Home',
        'lat': 11.5,
        'lng': 77.9,
        'startedAt': 1000000,
      });

      expect(entry.isRunning, isTrue);
      expect(entry.endedAt, isNull);
      expect(entry.latitude, 11.5);
    });
  });
}
