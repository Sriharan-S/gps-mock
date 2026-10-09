import 'package:flutter_test/flutter_test.dart';
import 'package:gps_mock/services/location_link.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  LinkLocation location(String input) {
    final result = LocationLinkParser.parse(input);
    expect(result, isA<LinkLocation>(), reason: input);
    return result as LinkLocation;
  }

  LinkInvalid invalid(String input) {
    final result = LocationLinkParser.parse(input);
    expect(result, isA<LinkInvalid>(), reason: input);
    return result as LinkInvalid;
  }

  group('geo: URIs', () {
    test('plain coordinates', () {
      final result = location('geo:13.0827,80.2707');
      expect(result.location.latitude, 13.0827);
      expect(result.location.longitude, 80.2707);
    });

    test('coordinates with altitude and parameters', () {
      final result = location('geo:13.08,80.27,12;u=35?z=15');
      expect(result.location.latitude, 13.08);
    });

    test('labelled point in q', () {
      final result =
          location('geo:0,0?q=13.0827,80.2707(Marina%20Beach)');
      expect(result.location.longitude, 80.2707);
      expect(result.label, 'Marina Beach');
    });

    test('address-only query needs a lookup', () {
      final result = LocationLinkParser.parse('geo:0,0?q=Eiffel+Tower');
      expect(result, isA<LinkPlaceQuery>());
      expect((result as LinkPlaceQuery).query, 'Eiffel Tower');
    });

    test('0,0 with no query is rejected', () {
      expect(invalid('geo:0,0').reason, contains('no location'));
    });

    test('out-of-range coordinates are rejected', () {
      expect(invalid('geo:123.4,80.2').reason, contains('out of range'));
    });

    test('malformed escapes do not throw', () {
      expect(
        LocationLinkParser.parse('geo:0,0?q=50%zz'),
        isA<LinkPlaceQuery>(),
      );
    });
  });

  group('Google Maps', () {
    test('place link prefers the pin over the viewport', () {
      final result = location(
        'https://www.google.com/maps/place/Marina+Beach/@13.05,80.28,15z/'
        'data=!4m6!3m5!1s0x0:0x0!8m2!3d13.0500!4d80.2824',
      );
      expect(result.location.latitude, 13.05);
      expect(result.location.longitude, 80.2824);
      expect(result.label, 'Marina Beach');
    });

    test('q= coordinates', () {
      final result = location('https://maps.google.com/?q=12.9716,77.5946');
      expect(result.location.latitude, 12.9716);
    });

    test('api=1 search query', () {
      final result = location(
        'https://www.google.com/maps/search/?api=1&query=12.97%2C77.59',
      );
      expect(result.location.longitude, 77.59);
    });

    test('viewport only', () {
      final result = location('https://www.google.com/maps/@12.97,77.59,14z');
      expect(result.location.latitude, 12.97);
    });

    test('directions destination', () {
      final result = location(
        'https://www.google.com/maps/dir/?api=1&destination=11.66,78.15',
      );
      expect(result.asDestination, isTrue);
    });

    test('named place without coordinates needs a lookup', () {
      final result = LocationLinkParser.parse(
        'https://www.google.com/maps/search/?api=1&query=Chennai+Central',
      );
      expect(result, isA<LinkPlaceQuery>());
    });

    test('short links must be followed', () {
      expect(
        LocationLinkParser.parse('https://maps.app.goo.gl/AbCdEf123'),
        isA<LinkShortUrl>(),
      );
    });

    test('consent page unwraps to the real link', () {
      final result = location(
        'https://consent.google.com/ml?continue='
        'https%3A%2F%2Fwww.google.com%2Fmaps%2F%4012.97%2C77.59%2C14z',
      );
      expect(result.location.latitude, 12.97);
    });
  });

  group('other map sites', () {
    test('OpenStreetMap marker', () {
      final result = location(
        'https://www.openstreetmap.org/?mlat=13.08&mlon=80.27#map=16/13.08/80.27',
      );
      expect(result.location.longitude, 80.27);
    });

    test('OpenStreetMap map fragment', () {
      final result =
          location('https://www.openstreetmap.org/#map=15/51.5072/-0.1276');
      expect(result.location.longitude, -0.1276);
    });

    test('Apple Maps', () {
      final result =
          location('https://maps.apple.com/?ll=37.33,-122.03&q=Cupertino');
      expect(result.label, 'Cupertino');
    });

    test('Waze', () {
      final result =
          location('https://waze.com/ul?ll=45.6906,-120.8104&navigate=yes');
      expect(result.asDestination, isTrue);
    });

    test('Bing Maps', () {
      final result = location('https://www.bing.com/maps?cp=47.6~-122.3');
      expect(result.location.latitude, 47.6);
    });
  });

  group('shared text', () {
    test('Google Maps share text keeps the place name', () {
      final result = LocationLinkParser.parse(
        'Marina Beach\nhttps://www.google.com/maps/@13.05,80.28,15z',
      );
      expect((result as LinkLocation).label, 'Marina Beach');
    });

    test('bare coordinates', () {
      final result = location('12.9716, 77.5946');
      expect(result.location.longitude, 77.5946);
    });

    test('trailing punctuation is not part of the link', () {
      location('Meet here: https://maps.google.com/?q=12.97,77.59.');
    });

    test('unsupported site is explained', () {
      final result = invalid('https://example.com/some/page');
      expect(result.unsupportedSite, isTrue);
      expect(result.reason, contains('example.com'));
    });

    test('text without a location is explained', () {
      expect(invalid('see you at the cafe').reason, contains('No map link'));
    });

    test('empty text is explained', () {
      expect(invalid('   ').reason, contains('empty'));
    });
  });

  group('LocationLinkResolver', () {
    test('follows a short link to its coordinates', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'maps.app.goo.gl') {
          return http.Response('', 302, headers: {
            'location': 'https://www.google.com/maps/@12.97,77.59,14z',
          });
        }
        return http.Response('', 200);
      });
      final result = await LocationLinkResolver(client: client)
          .resolve('https://maps.app.goo.gl/abc');
      expect(result, isA<LinkLocation>());
    });

    test('a dead short link is reported, not mistaken for offline', () async {
      final client = MockClient((_) async => http.Response('gone', 404));
      final result = await LocationLinkResolver(client: client)
          .resolve('https://maps.app.goo.gl/expired');
      expect((result as LinkInvalid).reason, contains('expired'));
    });

    test('network failure is reported as such', () async {
      final client = MockClient((_) async => throw http.ClientException('x'));
      final result = await LocationLinkResolver(client: client)
          .resolve('https://maps.app.goo.gl/abc');
      expect((result as LinkInvalid).reason, contains('connection'));
    });

    test('a short link to an unsupported site is explained', () async {
      final client = MockClient((_) async => http.Response('', 301,
          headers: {'location': 'https://example.com/promo'}));
      final result = await LocationLinkResolver(client: client)
          .resolve('https://maps.app.goo.gl/abc');
      expect(
        (result as LinkInvalid).reason,
        'The short link didn\'t lead to a location.',
      );
    });
  });
}
