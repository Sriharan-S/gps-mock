import 'dart:convert';

import 'package:gps_mock/models/offline_area.dart';
import 'package:gps_mock/utils/constants.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlaceSuggestion {
  final String name;
  final String description;
  final LatLng location;

  const PlaceSuggestion({
    required this.name,
    required this.description,
    required this.location,
  });
}

/// A place with a known extent — a city, district, state or country — used
/// when choosing an area to make available offline.
class PlaceArea {
  const PlaceArea({
    required this.name,
    required this.description,
    required this.southWest,
    required this.northEast,
    required this.level,
    this.country = '',
    this.state = '',
    this.district = '',
  });

  final String name;
  final String description;
  final LatLng southWest;
  final LatLng northEast;
  final AreaLevel level;
  final String country;
  final String state;
  final String district;
}

/// Place search backed by Photon (photon.komoot.io) — a free, keyless
/// OpenStreetMap geocoder built for search-as-you-type.
class SearchService {
  final http.Client _client = http.Client();

  /// Searches for places matching [query], biased towards [near] when given.
  /// Returns an empty list on any failure so the UI can degrade gracefully.
  Future<List<PlaceSuggestion>> search(String query, {LatLng? near}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];

    final params = <String, String>{'q': trimmed, 'limit': '6'};
    if (near != null) {
      params['lat'] = near.latitude.toStringAsFixed(4);
      params['lon'] = near.longitude.toStringAsFixed(4);
    }
    final uri = Uri.parse(
      AppConstants.photonBaseUrl,
    ).replace(queryParameters: params);

    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': AppConstants.userAgent})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      return parsePhotonResponse(response.body);
    } catch (_) {
      return const [];
    }
  }

  /// Accepts "12.9716, 77.5946" and the same with a space or semicolon
  /// separator — pasting coordinates is the fastest way to mock an exact
  /// point, so it is treated as a first-class query.
  static LatLng? parseCoordinates(String input) {
    final match = RegExp(
      r'^\s*(-?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)\s*$',
    ).firstMatch(input);
    if (match == null) return null;
    final lat = double.tryParse(match.group(1)!);
    final lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LatLng(lat, lng);
  }

  /// Parses a Photon GeoJSON FeatureCollection into suggestions.
  static List<PlaceSuggestion> parsePhotonResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final features = (json['features'] as List?) ?? const [];
    final results = <PlaceSuggestion>[];
    for (final feature in features) {
      final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
      final coords = feature['geometry']?['coordinates'] as List?;
      if (coords == null || coords.length < 2) continue;
      final name = (props['name'] ?? props['street'] ?? '') as String;
      if (name.isEmpty) continue;
      final parts =
          [
                props['street'],
                props['district'],
                props['city'],
                props['state'],
                props['country'],
              ]
              .whereType<String>()
              .where((part) => part.isNotEmpty && part != name)
              .toList();
      results.add(
        PlaceSuggestion(
          name: name,
          description: parts.take(3).join(', '),
          location: LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          ),
        ),
      );
    }
    return results;
  }

  /// Searches for administrative areas that have a usable bounding box.
  /// Photon returns an `extent` for places big enough to have one, plus the
  /// admin ancestry used to nest downloads in the offline list.
  Future<List<PlaceArea>> searchAreas(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];
    final uri = Uri.parse(AppConstants.photonBaseUrl).replace(
      queryParameters: {'q': trimmed, 'limit': '8'},
    );
    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': AppConstants.userAgent})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];
      return parsePhotonAreas(response.body);
    } catch (_) {
      return const [];
    }
  }

  /// Parses Photon features that carry an `extent` into [PlaceArea]s.
  /// Features without one (a house, a shop) are skipped — there is nothing
  /// sensible to download for them.
  static List<PlaceArea> parsePhotonAreas(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final features = (json['features'] as List?) ?? const [];
    final results = <PlaceArea>[];
    for (final feature in features) {
      final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
      final extent = props['extent'] as List?;
      if (extent == null || extent.length < 4) continue;
      final name = (props['name'] ?? '') as String;
      if (name.isEmpty) continue;

      // Photon's extent is [minLon, maxLat, maxLon, minLat].
      final minLon = (extent[0] as num).toDouble();
      final maxLat = (extent[1] as num).toDouble();
      final maxLon = (extent[2] as num).toDouble();
      final minLat = (extent[3] as num).toDouble();

      final country = (props['country'] ?? '') as String;
      final state = (props['state'] ?? '') as String;
      final district = (props['county'] ?? props['district'] ?? '') as String;
      final parts = [state, country]
          .where((part) => part.isNotEmpty && part != name)
          .toList();

      results.add(
        PlaceArea(
          name: name,
          description: parts.join(', '),
          southWest: LatLng(minLat, minLon),
          northEast: LatLng(maxLat, maxLon),
          level: AreaLevelInfo.fromOsmType(props['type'] as String?),
          country: country,
          state: state,
          district: district,
        ),
      );
    }
    return results;
  }
}
