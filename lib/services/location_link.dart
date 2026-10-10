import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// What an incoming link or shared text asks GPS Mock to do.
sealed class LinkResult {
  const LinkResult();
}

/// A location was found. [asDestination] is set for directions links, which
/// name where to go rather than a place to stand.
class LinkLocation extends LinkResult {
  const LinkLocation(this.location, {this.label, this.asDestination = false});

  final LatLng location;
  final String? label;
  final bool asDestination;
}

/// The link names a place but carries no coordinates (e.g. `geo:0,0?q=Eiffel
/// Tower`); it has to be looked up by name.
class LinkPlaceQuery extends LinkResult {
  const LinkPlaceQuery(this.query, {this.asDestination = false});

  final String query;
  final bool asDestination;
}

/// A short link (maps.app.goo.gl, osm.org/go …) that must be followed to the
/// full URL before it can be read.
class LinkShortUrl extends LinkResult {
  const LinkShortUrl(this.url);

  final Uri url;
}

/// Nothing usable — [reason] says why, in words fit for the user.
class LinkInvalid extends LinkResult {
  const LinkInvalid(this.reason, {this.unsupportedSite = false});

  final String reason;

  /// The link is fine but comes from a site GPS Mock can't read.
  final bool unsupportedSite;
}

/// Reads locations out of map links and shared text.
///
/// Supported: `geo:` URIs, Google Maps (full and short links), OpenStreetMap,
/// Apple Maps, Waze and Bing Maps links, and bare "lat, lng" text. Parsing is
/// pure; following short links is done separately by [LocationLinkResolver].
class LocationLinkParser {
  const LocationLinkParser._();

  static final _urlPattern = RegExp(r'(?:https?://|geo:)[^\s<>"]+',
      caseSensitive: false);
  static final _pairPattern = RegExp(
    r'(?<![\d.])([-+]?\d{1,3}(?:\.\d+)?)\s*,\s*([-+]?\d{1,3}(?:\.\d+)?)(?![\d.])',
  );

  /// Parses whatever was shared or opened: a bare link, a link inside some
  /// text (Google Maps shares "Place name\nhttps://…"), or coordinates.
  static LinkResult parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return const LinkInvalid('The shared text was empty.');

    final match = _urlPattern.firstMatch(text);
    if (match != null) {
      // Trailing punctuation from prose ("… here: https://…).") is not part
      // of the link.
      final raw = _trimTrailingPunctuation(match.group(0)!);
      final result = parseLink(raw);
      // Text before the link is usually the place name.
      final before = text.substring(0, match.start).trim();
      if (result is LinkLocation && result.label == null && before.isNotEmpty) {
        return LinkLocation(
          result.location,
          label: before.split('\n').first.trim(),
          asDestination: result.asDestination,
        );
      }
      return result;
    }

    final pair = _pairPattern.firstMatch(text);
    if (pair != null) {
      return _checked(pair.group(1)!, pair.group(2)!) ??
          const LinkInvalid('The coordinates are out of range.');
    }
    return const LinkInvalid(
      'No map link or coordinates were found in what was shared.',
    );
  }

  /// Drops sentence punctuation stuck to the end of a link, keeping a
  /// closing parenthesis that belongs to it (`geo:…?q=lat,lng(Label)`).
  static String _trimTrailingPunctuation(String link) {
    var result = link;
    while (result.isNotEmpty) {
      final last = result[result.length - 1];
      final unbalanced = last == ')' &&
          ')'.allMatches(result).length > '('.allMatches(result).length;
      if ('.,;!?'.contains(last) || unbalanced) {
        result = result.substring(0, result.length - 1);
      } else {
        break;
      }
    }
    return result;
  }

  /// Parses a single link.
  static LinkResult parseLink(String raw) {
    if (raw.toLowerCase().startsWith('geo:')) return _parseGeo(raw);

    final Uri uri;
    try {
      uri = Uri.parse(raw);
    } on FormatException {
      return const LinkInvalid('The link is malformed.');
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return const LinkInvalid('The link is malformed.');

    if (_isShortLink(host, uri.path)) return LinkShortUrl(uri);
    if (host == 'consent.google.com') {
      // Google's cookie-consent interstitial wraps the real link.
      final next = uri.queryParameters['continue'];
      return next == null
          ? const LinkInvalid('The link only leads to a Google consent page.')
          : parseLink(next);
    }
    if (_isGoogleMaps(host, uri.path)) return _parseGoogle(uri);
    if (host.endsWith('openstreetmap.org') || host == 'osm.org') {
      return _parseOsm(uri);
    }
    if (host == 'maps.apple.com' || host == 'maps.apple') {
      return _parseApple(uri);
    }
    if (host.endsWith('waze.com')) return _parseWaze(uri);
    if (host.endsWith('bing.com') && uri.path.startsWith('/maps')) {
      return _parseBing(uri);
    }

    // Unknown site: accept it only if it plainly carries coordinates.
    final generic = _genericCoordinates(uri);
    if (generic != null) return generic;
    return LinkInvalid(
      'Links from ${uri.host} aren\'t supported — share a Google Maps, '
      'OpenStreetMap, Apple Maps or Waze link, or plain coordinates.',
      unsupportedSite: true,
    );
  }

  // ------------------------------------------------------------------ geo:

  /// `geo:lat,lng[,alt][;crs=…;u=…][?q=lat,lng(Label)|q=address&z=…]`
  static LinkResult _parseGeo(String raw) {
    final body = raw.substring(4);
    final queryStart = body.indexOf('?');
    final path = _decode(
      (queryStart < 0 ? body : body.substring(0, queryStart)).split(';').first,
    ).trim();
    final query = queryStart < 0 ? '' : body.substring(queryStart + 1);
    final q = _queryValue(query, 'q');

    if (q != null && q.isNotEmpty) {
      final label = RegExp(r'\(([^)]*)\)\s*$').firstMatch(q)?.group(1)?.trim();
      final pair = _pairPattern.firstMatch(q);
      if (pair != null && pair.start == 0) {
        final location = _checked(pair.group(1)!, pair.group(2)!, label: label);
        return location ??
            const LinkInvalid('The coordinates in the link are out of range.');
      }
      return LinkPlaceQuery(q.replaceAll(RegExp(r'\([^)]*\)\s*$'), '').trim());
    }

    final parts = path.split(',');
    if (parts.length < 2) {
      return const LinkInvalid('The geo: link has no coordinates.');
    }
    final location = _checked(parts[0], parts[1]);
    if (location == null) {
      return const LinkInvalid('The coordinates in the link are out of range.');
    }
    if (location.location.latitude == 0 && location.location.longitude == 0) {
      return const LinkInvalid('The geo: link has no location in it (0,0).');
    }
    return location;
  }

  static String? _queryValue(String query, String key) {
    for (final part in query.split('&')) {
      final eq = part.indexOf('=');
      if (eq > 0 && part.substring(0, eq).toLowerCase() == key) {
        return _decode(part.substring(eq + 1)).trim();
      }
    }
    return null;
  }

  /// Percent-decodes a URI component, tolerating malformed escapes.
  static String _decode(String value) {
    final spaced = value.replaceAll('+', ' ');
    try {
      return Uri.decodeComponent(spaced);
    } on ArgumentError {
      return spaced;
    } on FormatException {
      return spaced;
    }
  }

  // --------------------------------------------------------------- Google

  static bool _isShortLink(String host, String path) =>
      host == 'maps.app.goo.gl' ||
      (host == 'goo.gl' && path.startsWith('/maps')) ||
      host == 'g.co' ||
      (host == 'osm.org' && path.startsWith('/go/')) ||
      host == 'waze.to';

  static bool _isGoogleMaps(String host, String path) {
    final google = RegExp(r'(^|\.)google\.[a-z.]+$').hasMatch(host);
    return (google && (host.startsWith('maps.') || path.startsWith('/maps'))) ||
        host == 'maps.google.com';
  }

  static LinkResult _parseGoogle(Uri uri) {
    final params = uri.queryParameters;
    final path = Uri.decodeComponent(uri.path);

    // Directions: …/maps/dir/?api=1&destination=… or ?daddr=…
    final destination = params['destination'] ?? params['daddr'];
    if (destination != null && destination.isNotEmpty) {
      return _coordsOrQuery(destination, asDestination: true);
    }

    // The place's own position, when the link points at a place.
    final pin = RegExp(r'!3d([-+]?\d+(?:\.\d+)?)!4d([-+]?\d+(?:\.\d+)?)')
        .firstMatch(path);
    final placeName = RegExp(r'/place/([^/@]+)').firstMatch(path)?.group(1);
    final label = placeName?.replaceAll('+', ' ').trim();
    if (pin != null) {
      return _checked(pin.group(1)!, pin.group(2)!, label: label) ??
          const LinkInvalid('The coordinates in the link are out of range.');
    }

    for (final key in ['q', 'query', 'll', 'center', 'sll']) {
      final value = params[key];
      if (value != null && value.isNotEmpty) {
        final result = _coordsOrQuery(value);
        if (result is LinkLocation || key == 'q' || key == 'query') {
          return result;
        }
      }
    }

    // /maps/place/<lat,lng> or /maps/search/<lat,+lng>
    final segment = RegExp(r'/(?:place|search)/([^/@]+)').firstMatch(path);
    if (segment != null) {
      final value = segment.group(1)!.replaceAll('+', ' ');
      final pair = _pairPattern.firstMatch(value);
      if (pair != null) {
        return _checked(pair.group(1)!, pair.group(2)!) ??
            const LinkInvalid('The coordinates in the link are out of range.');
      }
    }

    // The map viewport (/@lat,lng,zoom) — the best there is for a link that
    // only names a place; otherwise fall back to looking the name up.
    final viewport =
        RegExp(r'@([-+]?\d+(?:\.\d+)?),([-+]?\d+(?:\.\d+)?)').firstMatch(path);
    if (viewport != null) {
      return _checked(viewport.group(1)!, viewport.group(2)!, label: label) ??
          const LinkInvalid('The coordinates in the link are out of range.');
    }
    if (label != null && label.isNotEmpty) return LinkPlaceQuery(label);
    if (segment != null) {
      return LinkPlaceQuery(segment.group(1)!.replaceAll('+', ' ').trim());
    }
    return const LinkInvalid(
      'This Google Maps link doesn\'t point at a place.',
    );
  }

  /// A parameter that holds either "lat,lng" or a place name/address.
  static LinkResult _coordsOrQuery(String value, {bool asDestination = false}) {
    final trimmed = value.trim();
    final pair = _pairPattern.firstMatch(trimmed);
    if (pair != null && pair.start == 0) {
      final location = _checked(pair.group(1)!, pair.group(2)!);
      if (location == null) {
        return const LinkInvalid(
            'The coordinates in the link are out of range.');
      }
      return LinkLocation(location.location, asDestination: asDestination);
    }
    return LinkPlaceQuery(trimmed, asDestination: asDestination);
  }

  // ---------------------------------------------------------- other maps

  static LinkResult _parseOsm(Uri uri) {
    final params = uri.queryParameters;
    final mlat = params['mlat'];
    final mlon = params['mlon'];
    if (mlat != null && mlon != null) {
      return _checked(mlat, mlon) ??
          const LinkInvalid('The coordinates in the link are out of range.');
    }
    // #map=zoom/lat/lng
    final map = RegExp(r'map=\d+(?:\.\d+)?/([-+]?\d+(?:\.\d+)?)/([-+]?\d+(?:\.\d+)?)')
        .firstMatch(uri.fragment);
    if (map != null) {
      return _checked(map.group(1)!, map.group(2)!) ??
          const LinkInvalid('The coordinates in the link are out of range.');
    }
    final lat = params['lat'];
    final lon = params['lon'];
    if (lat != null && lon != null) {
      return _checked(lat, lon) ??
          const LinkInvalid('The coordinates in the link are out of range.');
    }
    final query = params['query'];
    if (query != null && query.isNotEmpty) return _coordsOrQuery(query);
    return const LinkInvalid(
      'This OpenStreetMap link doesn\'t point at a location.',
    );
  }

  static LinkResult _parseApple(Uri uri) {
    final params = uri.queryParameters;
    final destination = params['daddr'];
    if (destination != null && destination.isNotEmpty) {
      return _coordsOrQuery(destination, asDestination: true);
    }
    for (final key in ['ll', 'coordinate', 'sll']) {
      final value = params[key];
      if (value != null && value.isNotEmpty) {
        final result = _coordsOrQuery(value);
        if (result is LinkLocation) {
          return LinkLocation(result.location, label: params['q']);
        }
        if (result is LinkInvalid) return result;
      }
    }
    final query = params['q'] ?? params['address'];
    if (query != null && query.isNotEmpty) return _coordsOrQuery(query);
    return const LinkInvalid('This Apple Maps link doesn\'t point at a place.');
  }

  static LinkResult _parseWaze(Uri uri) {
    final params = uri.queryParameters;
    final ll = params['ll'] ?? params['latlng'];
    if (ll != null && ll.isNotEmpty) {
      final result = _coordsOrQuery(ll, asDestination: params['navigate'] == 'yes');
      if (result is! LinkPlaceQuery) return result;
    }
    final query = params['q'];
    if (query != null && query.isNotEmpty) return _coordsOrQuery(query);
    return const LinkInvalid('This Waze link doesn\'t point at a place.');
  }

  static LinkResult _parseBing(Uri uri) {
    final params = uri.queryParameters;
    final cp = params['cp'];
    if (cp != null) {
      final parts = cp.split('~');
      if (parts.length == 2) {
        return _checked(parts[0], parts[1]) ??
            const LinkInvalid('The coordinates in the link are out of range.');
      }
    }
    final query = params['where1'] ?? params['q'];
    if (query != null && query.isNotEmpty) return _coordsOrQuery(query);
    return const LinkInvalid('This Bing Maps link doesn\'t point at a place.');
  }

  /// Any link with lat/lng parameters or a "lat,lng" pair in its path.
  static LinkLocation? _genericCoordinates(Uri uri) {
    final params = uri.queryParameters;
    final lat = params['lat'] ?? params['latitude'];
    final lng = params['lng'] ?? params['lon'] ?? params['long'] ??
        params['longitude'];
    if (lat != null && lng != null) return _checked(lat, lng);
    return null;
  }

  /// Builds a location from two strings, or null when either isn't a number
  /// or lies outside the globe.
  static LinkLocation? _checked(String lat, String lng, {String? label}) {
    final latitude = double.tryParse(lat.trim());
    final longitude = double.tryParse(lng.trim());
    if (latitude == null || longitude == null) return null;
    if (latitude.isNaN || longitude.isNaN) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    return LinkLocation(
      LatLng(latitude, longitude),
      label: (label == null || label.isEmpty) ? null : label,
    );
  }
}

/// Follows short links to the full URL they stand for, and turns the final
/// result into a location or a reason it couldn't be found.
class LocationLinkResolver {
  LocationLinkResolver({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _maxRedirects = 6;

  /// Parses [input], following short links as needed. Never throws: network
  /// problems come back as [LinkInvalid] with an explanation.
  Future<LinkResult> resolve(String input) async {
    var result = LocationLinkParser.parse(input);
    for (var hop = 0; result is LinkShortUrl && hop < _maxRedirects; hop++) {
      final String? next;
      try {
        next = await _follow(result.url);
      } catch (_) {
        return const LinkInvalid(
          'Couldn\'t open the short link — check your internet connection '
          'and try again.',
        );
      }
      if (next == null) {
        return const LinkInvalid(
          'The short link didn\'t lead to a location. It may have expired.',
        );
      }
      result = LocationLinkParser.parseLink(next);
      if (result is LinkInvalid && result.unsupportedSite) {
        // "Links from <site> aren't supported" would blame the user for
        // where the short link happened to lead.
        return const LinkInvalid(
          'The short link didn\'t lead to a location.',
        );
      }
    }
    if (result is LinkShortUrl) {
      return const LinkInvalid('The short link redirected too many times.');
    }
    return result;
  }

  /// One redirect hop: where [url] redirects to, or null when it answers
  /// without redirecting. Throws when the server can't be reached.
  Future<String?> _follow(Uri url) async {
    final request = http.Request('GET', url)..followRedirects = false;
    request.headers['User-Agent'] = 'gps-mock (location link reader)';
    final response =
        await _client.send(request).timeout(const Duration(seconds: 10));
    await response.stream.drain<void>();
    final location = response.headers['location'];
    if (location == null || location.isEmpty) return null;
    return url.resolve(location).toString();
  }
}
