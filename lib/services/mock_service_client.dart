import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Snapshot of what the native MockingService is currently doing.
class MockStatus {
  final bool active;
  final String mode; // 'fixed' | 'route'
  final double latitude;
  final double longitude;
  final String label;
  final double progress; // 0..1 (route mode only)
  final int remainingSeconds;
  final double bearing;
  final double speedMps;
  final bool arrived;

  /// True while a fixed mock is parked on a route's destination, i.e. the
  /// simulation ran to completion and handed over.
  final bool arrivedFromRoute;
  final String? routeFile;

  const MockStatus({
    required this.active,
    this.mode = 'fixed',
    this.latitude = 0,
    this.longitude = 0,
    this.label = '',
    this.progress = 0,
    this.remainingSeconds = 0,
    this.bearing = 0,
    this.speedMps = 0,
    this.arrived = false,
    this.arrivedFromRoute = false,
    this.routeFile,
  });

  static const inactive = MockStatus(active: false);

  factory MockStatus.fromMap(Map map) => MockStatus(
        active: map['active'] == true,
        mode: (map['mode'] as String?) ?? 'fixed',
        latitude: (map['lat'] as num?)?.toDouble() ?? 0,
        longitude: (map['lng'] as num?)?.toDouble() ?? 0,
        label: (map['label'] as String?) ?? '',
        progress: (map['progress'] as num?)?.toDouble() ?? 0,
        remainingSeconds: (map['remainingSeconds'] as num?)?.toInt() ?? 0,
        bearing: (map['bearing'] as num?)?.toDouble() ?? 0,
        speedMps: (map['speedMps'] as num?)?.toDouble() ?? 0,
        arrived: map['arrived'] == true,
        arrivedFromRoute: map['arrivedFromRoute'] == true,
        routeFile: map['routeFile'] as String?,
      );
}

class MockServiceClient {
  static const platform = MethodChannel('com.mockgps/service');

  Future<void> startMocking(
    double lat,
    double lng, {
    String? label,
    String? favoriteId,
  }) async {
    await platform.invokeMethod('startMocking', {
      'lat': lat,
      'lng': lng,
      'label': label,
      'favoriteId': favoriteId,
    });
  }

  Future<void> startRoute({
    required String routeFilePath,
    required int durationSeconds,
    required String label,
    String? fromLabel,
    String? toLabel,
    double? distanceMeters,
    String? stopsJson,
  }) async {
    await platform.invokeMethod('startRoute', {
      'routeFile': routeFilePath,
      'durationSeconds': durationSeconds,
      'label': label,
      'fromLabel': fromLabel,
      'toLabel': toLabel,
      'distanceMeters': distanceMeters,
      'stopsJson': stopsJson,
    });
  }

  /// Past mock sessions recorded natively by the service (newest last), as
  /// a JSON array string; empty array when none.
  Future<String> getHistoryJson() async {
    try {
      return await platform.invokeMethod<String>('getHistory') ?? '[]';
    } catch (_) {
      return '[]';
    }
  }

  Future<void> clearHistory() async {
    try {
      await platform.invokeMethod('clearHistory');
    } catch (_) {
      // Non-critical.
    }
  }

  Future<void> stopMocking() async {
    try {
      await platform.invokeMethod('stopMocking');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop mocking: '${e.message}'.");
    }
  }

  /// Whether this app is currently selected as the mock location app in
  /// Developer Options.
  Future<bool> isMockLocationApp() async {
    try {
      return await platform.invokeMethod<bool>('isMockLocationApp') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<MockStatus> getMockStatus() async {
    try {
      final map = await platform.invokeMethod<Map>('getMockStatus');
      if (map == null) return MockStatus.inactive;
      return MockStatus.fromMap(map);
    } catch (_) {
      return MockStatus.inactive;
    }
  }

  /// Mirrors the favorites list into native storage so quick-settings tiles
  /// and widgets can read it without the Flutter engine running.
  Future<void> syncFavorites(String favoritesJson) async {
    try {
      await platform.invokeMethod('syncFavorites', {'json': favoritesJson});
    } catch (_) {
      // Non-critical: tiles/widgets just keep the previous snapshot.
    }
  }

  Future<void> openDeveloperSettings() async {
    try {
      await platform.invokeMethod('openDeveloperSettings');
    } on PlatformException catch (e) {
      debugPrint("Failed to open settings: '${e.message}'.");
    }
  }
}
