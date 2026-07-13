import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gps_mock/utils/constants.dart';
import 'package:http/http.dart' as http;

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;

  /// The realistic driving duration estimated by OSRM.
  final double osrmDurationSeconds;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.osrmDurationSeconds,
  });
}

class RouteException implements Exception {
  final String message;
  const RouteException(this.message);

  @override
  String toString() => message;
}

/// Road routing backed by the public OSRM server (router.project-osrm.org) —
/// free, keyless, OpenStreetMap-based driving routes.
class RouteService {
  final http.Client _client = http.Client();

  Future<RouteResult> fetchRoute(LatLng origin, LatLng destination) async {
    final uri = Uri.parse(
      "${AppConstants.osrmRouteBaseUrl}"
      "${origin.longitude},${origin.latitude};"
      "${destination.longitude},${destination.latitude}"
      "?overview=full&geometries=geojson",
    );

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': AppConstants.userAgent})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const RouteException(
        "Could not reach the routing service — check your connection.",
      );
    }
    if (response.statusCode != 200) {
      throw RouteException(
        "Routing service error (HTTP ${response.statusCode}). Try again.",
      );
    }
    return parseOsrmResponse(response.body);
  }

  /// Parses an OSRM route response (GeoJSON geometry).
  static RouteResult parseOsrmResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['code'] != 'Ok') {
      throw const RouteException("No drivable route found between these points.");
    }
    final routes = json['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw const RouteException("No drivable route found between these points.");
    }
    final route = routes.first as Map<String, dynamic>;
    final coords = route['geometry']?['coordinates'] as List?;
    if (coords == null || coords.length < 2) {
      throw const RouteException("The route geometry is missing.");
    }
    final points = coords
        .map<LatLng>(
          (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
        )
        .toList();
    return RouteResult(
      points: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      osrmDurationSeconds: (route['duration'] as num).toDouble(),
    );
  }
}
