import 'package:flutter_test/flutter_test.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/models/mock_history_entry.dart';
import 'package:gps_mock/services/route_service.dart';
import 'package:gps_mock/services/search_service.dart';
import 'package:gps_mock/services/update_service.dart';
import 'package:latlong2/latlong.dart';

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

  group('SearchService.parseCoordinates', () {
    test('parses "lat, lng" with and without spaces', () {
      expect(
        SearchService.parseCoordinates('12.9716, 77.5946'),
        const LatLng(12.9716, 77.5946),
      );
      expect(
        SearchService.parseCoordinates('-33.8688 151.2093'),
        const LatLng(-33.8688, 151.2093),
      );
      expect(
        SearchService.parseCoordinates(' 51;-0.12 '),
        const LatLng(51, -0.12),
      );
    });

    test('rejects place names and out-of-range values', () {
      expect(SearchService.parseCoordinates('Chennai'), isNull);
      expect(SearchService.parseCoordinates('91.0, 10.0'), isNull);
      expect(SearchService.parseCoordinates('10.0, 181.0'), isNull);
      expect(SearchService.parseCoordinates('12.97'), isNull);
    });
  });

  group('UpdateService.isNewer', () {
    test('compares versions numerically, not as strings', () {
      expect(UpdateService.isNewer('2.10.0', '2.9.0'), isTrue);
      expect(UpdateService.isNewer('2.1.0', '2.1.0'), isFalse);
      expect(UpdateService.isNewer('2.0.9', '2.1.0'), isFalse);
      expect(UpdateService.isNewer('3.0.0', '2.99.99'), isTrue);
    });

    test('tolerates v prefixes, build suffixes and short versions', () {
      expect(UpdateService.isNewer('v2.2.0', '2.1.0'), isTrue);
      expect(UpdateService.isNewer('v2.2.0+7', '2.2.0'), isFalse);
      expect(UpdateService.isNewer('2.2', '2.1.9'), isTrue);
      expect(UpdateService.isNewer('2.1', '2.1.0'), isFalse);
    });

    test('treats an unknown installed version as out of date', () {
      expect(UpdateService.isNewer('1.0.0', ''), isTrue);
      expect(UpdateService.isNewer('', '1.0.0'), isFalse);
    });
  });

  group('UpdateService.looksLikeVersion', () {
    test('accepts dotted numeric versions', () {
      expect(UpdateService.looksLikeVersion('2.1.0'), isTrue);
      expect(UpdateService.looksLikeVersion('v2.1.0'), isTrue);
      expect(UpdateService.looksLikeVersion('2.1.0+3'), isTrue);
      expect(UpdateService.looksLikeVersion('3'), isTrue);
    });

    test('rejects date-style tags, which must not be compared numerically', () {
      expect(UpdateService.looksLikeVersion('v2026-07-29-19'), isFalse);
      expect(UpdateService.looksLikeVersion('nightly'), isFalse);
      expect(UpdateService.looksLikeVersion(''), isFalse);
    });
  });

  group('UpdateService.parseRelease', () {
    test('picks the APK asset and normalises the tag', () {
      const body = '''
      {
        "tag_name": "v2.3.0",
        "name": "GPS Mock 2.3.0",
        "body": "Adds offline maps.",
        "html_url": "https://github.com/Sriharan-S/gps-mock/releases/tag/v2.3.0",
        "published_at": "2026-08-30T04:00:00Z",
        "assets": [
          {"name": "notes.txt", "browser_download_url": "https://x/notes.txt", "size": 10},
          {"name": "gps-mock-2.3.0.apk", "browser_download_url": "https://x/app.apk", "size": 20971520}
        ]
      }
      ''';
      final release = UpdateService.parseRelease(body)!;
      expect(release.tag, 'v2.3.0');
      expect(release.version, '2.3.0');
      expect(release.name, 'GPS Mock 2.3.0');
      expect(release.apkUrl, 'https://x/app.apk');
      expect(release.hasApk, isTrue);
      expect(release.sizeLabel, '20.0 MB');
    });

    test('reports a release with no APK so the caller opens the page', () {
      const body = '{"tag_name": "v2.4.0", "assets": []}';
      final release = UpdateService.parseRelease(body)!;
      expect(release.hasApk, isFalse);
      expect(release.version, '2.4.0');
    });

    test('ignores drafts', () {
      const body = '{"tag_name": "v9.0.0", "draft": true, "assets": []}';
      expect(UpdateService.parseRelease(body), isNull);
    });
  });
}
