import 'dart:async';
import 'dart:math' as math;

import 'package:gps_mock/models/offline_area.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// Progress of an in-flight area download.
class OfflineDownloadProgress {
  const OfflineDownloadProgress({
    required this.name,
    required this.fraction,
    required this.completedTiles,
    required this.requiredTiles,
    required this.bytes,
  });

  final String name;
  final double fraction;
  final int completedTiles;
  final int requiredTiles;
  final int bytes;
}

/// Downloads and manages map tiles stored on the device, on top of MapLibre's
/// offline region database.
///
/// Regions are bounding boxes at a bounded zoom range — never the whole world.
/// Each carries metadata naming it and recording where it sits in the
/// country → state → district → city hierarchy, so the UI can group and
/// delete by level.
class OfflineMapService {
  /// Refuses anything past this many resources. A country at street zoom runs
  /// to millions; this keeps a mis-tap from filling the device.
  static const maxTiles = 120000;

  /// Multiplier from "tiles in the pyramid" to "resources MapLibre fetches".
  /// A style has several sources plus glyphs and sprites, so the raw tile
  /// count understates the real download by roughly this much — measured
  /// against actual downloads rather than guessed.
  static const _resourceFactor = 5;

  /// A hard ceiling MapLibre itself enforces on the offline database.
  static const _tileCountLimit = 200000;

  bool _limitSet = false;

  Future<void> _ensureLimits() async {
    if (_limitSet) return;
    _limitSet = true;
    try {
      await ml.setOfflineTileCountLimit(_tileCountLimit);
      // Free tile servers rate-limit aggressive parallel fetches.
      await ml.setOfflineMaxConcurrentRequests(
        maxRequests: 4,
        maxRequestsPerHost: 4,
      );
    } catch (_) {
      // Defaults are fine if the platform rejects the tuning.
    }
  }

  /// Every area currently stored on the device.
  Future<List<OfflineArea>> listAreas() async {
    try {
      final regions = await ml.getListOfRegions();
      return regions.map(_toArea).toList();
    } catch (_) {
      return const [];
    }
  }

  OfflineArea _toArea(ml.OfflineRegion region) {
    final metadata = region.metadata;
    final bounds = region.definition.bounds;
    return OfflineArea(
      id: region.id,
      name: (metadata['name'] as String?) ?? 'Downloaded area',
      level: AreaLevel.values.asNameMap()[metadata['level']] ?? AreaLevel.spot,
      southWest: LatLng(
        bounds.southwest.latitude,
        bounds.southwest.longitude,
      ),
      northEast: LatLng(
        bounds.northeast.latitude,
        bounds.northeast.longitude,
      ),
      country: (metadata['country'] as String?) ?? '',
      state: (metadata['state'] as String?) ?? '',
      district: (metadata['district'] as String?) ?? '',
      sizeBytes: (metadata['sizeBytes'] as num?)?.toInt() ?? 0,
      styleUrl: (metadata['styleUrl'] as String?) ?? '',
    );
  }

  /// How many tiles a box spans across a zoom range — the honest size signal
  /// to show before committing to a download.
  static int estimateTiles(
    LatLng southWest,
    LatLng northEast,
    double minZoom,
    double maxZoom,
  ) =>
      _pyramidTiles(southWest, northEast, minZoom, maxZoom) * _resourceFactor;

  static int _pyramidTiles(
    LatLng southWest,
    LatLng northEast,
    double minZoom,
    double maxZoom,
  ) {
    var total = 0;
    for (var z = minZoom.floor(); z <= maxZoom.floor(); z++) {
      final scale = math.pow(2, z).toDouble();
      final x1 = _lonToTile(southWest.longitude, scale);
      final x2 = _lonToTile(northEast.longitude, scale);
      final y1 = _latToTile(northEast.latitude, scale);
      final y2 = _latToTile(southWest.latitude, scale);
      final across = (x2 - x1).abs().floor() + 1;
      final down = (y2 - y1).abs().floor() + 1;
      total += across * down;
    }
    return total;
  }

  static double _lonToTile(double lon, double scale) =>
      (lon + 180) / 360 * scale;

  static double _latToTile(double lat, double scale) {
    final rad = lat * math.pi / 180;
    return (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) /
        2 *
        scale;
  }

  /// Rough bytes-on-disk for a resource count, calibrated against measured
  /// downloads (~20 KB per resource for these vector styles).
  static int estimateBytes(int tiles) => tiles * 20 * 1024;

  /// Downloads [area]'s tiles for [styleUrl].
  ///
  /// Throws [OfflineTooLargeException] when the request would exceed
  /// [maxTiles]. Reports progress through [onProgress].
  Future<OfflineArea> download({
    required String name,
    required AreaLevel level,
    required LatLng southWest,
    required LatLng northEast,
    required String styleUrl,
    String country = '',
    String state = '',
    String district = '',
    void Function(OfflineDownloadProgress progress)? onProgress,
  }) async {
    await _ensureLimits();
    final (minZoom, maxZoom) = level.zoomRange;
    final tiles = estimateTiles(southWest, northEast, minZoom, maxZoom);
    if (tiles > maxTiles) {
      throw OfflineTooLargeException(name, tiles);
    }

    final area = OfflineArea(
      id: -1,
      name: name,
      level: level,
      southWest: southWest,
      northEast: northEast,
      country: country,
      state: state,
      district: district,
      sizeBytes: 0,
      styleUrl: styleUrl,
    );

    var bytes = 0;
    final finished = Completer<void>();
    final region = await ml.downloadOfflineRegion(
      ml.OfflineRegionDefinition(
        bounds: ml.LatLngBounds(
          southwest: ml.LatLng(southWest.latitude, southWest.longitude),
          northeast: ml.LatLng(northEast.latitude, northEast.longitude),
        ),
        mapStyleUrl: styleUrl,
        minZoom: minZoom,
        maxZoom: maxZoom,
      ),
      metadata: area.toMetadata(),
      onEvent: (event) {
        if (event is ml.InProgress) {
          bytes = event.completedResourceSize;
          onProgress?.call(
            OfflineDownloadProgress(
              name: name,
              fraction: (event.progress / 100).clamp(0.0, 1.0),
              completedTiles: event.completedResourceCount,
              requiredTiles: event.requiredResourceCount,
              bytes: event.completedResourceSize,
            ),
          );
        } else if (event is ml.Success) {
          if (!finished.isCompleted) finished.complete();
        } else if (event is ml.Error) {
          if (!finished.isCompleted) {
            finished.completeError(
              OfflineDownloadException(
                event.cause.message ?? 'The download failed',
              ),
            );
          }
        }
      },
    );

    // The future above resolves as soon as the download is under way, so wait
    // for the terminal event before reporting a size or declaring success.
    await finished.future;

    // Record the finished size so the list can show it without re-measuring.
    final stored = area.copyWith(sizeBytes: bytes);
    try {
      await ml.updateOfflineRegionMetadata(region.id, stored.toMetadata());
    } catch (_) {
      // Non-critical: the area still works, it just shows an unknown size.
    }
    return _toArea(region).copyWith(sizeBytes: bytes);
  }

  /// Deletes one area's tiles.
  Future<void> deleteArea(int id) async {
    await ml.deleteOfflineRegion(id);
    try {
      // Tiles shared with no other region would otherwise linger in the
      // ambient cache and keep occupying space.
      await ml.clearAmbientCache();
    } catch (_) {
      // Best effort.
    }
  }

  /// Deletes several areas — used when a country or state row is removed.
  Future<void> deleteAreas(Iterable<int> ids) async {
    for (final id in ids) {
      try {
        await ml.deleteOfflineRegion(id);
      } catch (_) {
        // Keep going; one failure shouldn't strand the rest.
      }
    }
    try {
      await ml.clearAmbientCache();
    } catch (_) {}
  }

  /// Wipes every downloaded area.
  Future<void> deleteEverything() async {
    await ml.resetOfflineDatabase();
  }
}

class OfflineTooLargeException implements Exception {
  const OfflineTooLargeException(this.name, this.tiles);

  final String name;
  final int tiles;

  @override
  String toString() =>
      '$name needs about $tiles tiles, past the '
      '${OfflineMapService.maxTiles} tile limit.';
}

class OfflineDownloadException implements Exception {
  const OfflineDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
