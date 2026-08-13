import 'package:latlong2/latlong.dart';

/// Thrown when imported GPX/coordinate content can't be turned into a route.
class RouteImportException implements Exception {
  final String message;
  const RouteImportException(this.message);

  @override
  String toString() => message;
}

/// A route parsed from an imported GPX file or a pasted list of coordinates.
class ImportedRoute {
  /// The ordered points to simulate.
  final List<LatLng> points;

  /// Total length of the polyline, in meters (Haversine sum).
  final double distanceMeters;

  /// Elapsed time between the first and last GPX timestamp, when the track
  /// carries `<time>` tags. Lets an imported recording be replayed at roughly
  /// its original pace. Null for coordinate lists or timeless tracks.
  final double? recordedDurationSeconds;

  /// A human-friendly name (GPX `<name>` or the source file name), if any.
  final String? name;

  const ImportedRoute({
    required this.points,
    required this.distanceMeters,
    this.recordedDurationSeconds,
    this.name,
  });
}

/// Turns user-supplied GPX tracks or coordinate lists into a simulatable
/// route. Pure parsing — no I/O, no dependencies beyond [LatLng] — so it can
/// be unit-tested directly.
class RouteImportService {
  static const Distance _distance = Distance();

  /// Parses [content], auto-detecting whether it is GPX XML or a plain list
  /// of coordinates. [sourceName] (e.g. a file name) is used as a fallback
  /// route name. Throws [RouteImportException] on anything unusable.
  static ImportedRoute parse(String content, {String? sourceName}) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw const RouteImportException("There is nothing to import.");
    }

    final isGpx = _looksLikeGpx(trimmed);
    final points =
        isGpx ? parseGpx(trimmed) : parseCoordinateList(trimmed);
    final name = _cleanName(
      (isGpx ? _gpxName(trimmed) : null) ?? sourceName,
    );

    return ImportedRoute(
      points: points,
      distanceMeters: polylineLength(points),
      recordedDurationSeconds: isGpx ? _gpxRecordedSeconds(trimmed) : null,
      name: name,
    );
  }

  // ------------------------------------------------------------------- GPX

  /// Extracts the ordered points of a GPX document, preferring a recorded
  /// track (`<trkpt>`), then a planned route (`<rtept>`), then loose
  /// waypoints (`<wpt>`).
  static List<LatLng> parseGpx(String xml) {
    var points = _pointElements(xml, 'trkpt');
    if (points.isEmpty) points = _pointElements(xml, 'rtept');
    if (points.isEmpty) points = _pointElements(xml, 'wpt');
    if (points.length < 2) {
      throw const RouteImportException(
        "The GPX file needs at least two track points.",
      );
    }
    return points;
  }

  static List<LatLng> _pointElements(String xml, String tag) {
    final points = <LatLng>[];
    // Matches e.g. <trkpt lat="12.3" lon="45.6"> or self-closing variants,
    // regardless of attribute order.
    final element = RegExp('<$tag\\b([^>]*)>', caseSensitive: false);
    for (final match in element.allMatches(xml)) {
      final attrs = match.group(1) ?? '';
      final lat = _attr(attrs, 'lat');
      final lon = _attr(attrs, 'lon');
      if (lat != null &&
          lon != null &&
          _validLat(lat) &&
          _validLon(lon)) {
        points.add(LatLng(lat, lon));
      }
    }
    return points;
  }

  static double? _attr(String attrs, String name) {
    final match = RegExp(
      '$name\\s*=\\s*["\']\\s*(-?\\d+(?:\\.\\d+)?)',
      caseSensitive: false,
    ).firstMatch(attrs);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  static String? _gpxName(String xml) {
    final match = RegExp(
      '<name>\\s*([^<]+?)\\s*</name>',
      caseSensitive: false,
    ).firstMatch(xml);
    return match?.group(1);
  }

  /// Elapsed seconds between the first and last `<time>` inside the track
  /// data. Best-effort: returns null when fewer than two parsable times
  /// exist, so a timeless track simply falls back to an estimated pace.
  static double? _gpxRecordedSeconds(String xml) {
    final firstPoint = xml.toLowerCase().indexOf('<trkpt');
    final scope = firstPoint >= 0 ? xml.substring(firstPoint) : xml;
    final times = RegExp(
      '<time>\\s*([^<]+?)\\s*</time>',
      caseSensitive: false,
    )
        .allMatches(scope)
        .map((m) => DateTime.tryParse(m.group(1)!.trim()))
        .whereType<DateTime>()
        .toList();
    if (times.length < 2) return null;
    final seconds =
        times.last.difference(times.first).inSeconds.toDouble();
    return seconds > 0 ? seconds : null;
  }

  // ------------------------------------------------------- coordinate lists

  /// Parses a newline- or semicolon-separated list of `lat, lon` pairs.
  /// Coordinates may be split by commas or whitespace; extra columns (e.g.
  /// elevation) are ignored, and `#` / `//` lines are treated as comments.
  static List<LatLng> parseCoordinateList(String text) {
    final points = <LatLng>[];
    for (final raw in text.split(RegExp(r'[\r\n;]+'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
        continue;
      }
      final parts = line
          .split(RegExp(r'[\s,]+'))
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length < 2) {
        throw RouteImportException('Could not read coordinates from "$line".');
      }
      final lat = double.tryParse(parts[0]);
      final lon = double.tryParse(parts[1]);
      if (lat == null || lon == null) {
        throw RouteImportException('Could not read coordinates from "$line".');
      }
      if (!_validLat(lat) || !_validLon(lon)) {
        throw RouteImportException('Coordinates out of range in "$line".');
      }
      points.add(LatLng(lat, lon));
    }
    if (points.length < 2) {
      throw const RouteImportException(
        "Provide at least two coordinates to build a route.",
      );
    }
    return points;
  }

  // --------------------------------------------------------------- helpers

  /// Total Haversine length of a polyline, in meters.
  static double polylineLength(List<LatLng> points) {
    double total = 0;
    for (var i = 1; i < points.length; i++) {
      total += _distance(points[i - 1], points[i]);
    }
    return total;
  }

  static bool _looksLikeGpx(String s) {
    final lower = s.toLowerCase();
    final head = lower.length > 256 ? lower.substring(0, 256) : lower;
    return head.contains('<?xml') ||
        head.contains('<gpx') ||
        lower.contains('<trkpt') ||
        lower.contains('<rtept') ||
        lower.contains('<wpt');
  }

  static String? _cleanName(String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    // Drop a trailing .gpx/.txt extension when the name came from a file.
    return trimmed.replaceAll(RegExp(r'\.(gpx|txt)$', caseSensitive: false), '');
  }

  static bool _validLat(double v) => v >= -90 && v <= 90;
  static bool _validLon(double v) => v >= -180 && v <= 180;
}
