import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gps_mock/utils/constants.dart';
import 'package:http/http.dart' as http;

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
}
