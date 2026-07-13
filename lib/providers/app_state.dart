import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/services/mock_service_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A one-shot request asking the map to move its camera. The home screen
/// tracks the token so each request is animated exactly once.
class CameraRequest {
  final LatLng target;
  final double zoom;
  final int token;
  const CameraRequest(this.target, this.zoom, this.token);
}

enum MockToggleResult { started, stopped, needsSetup, noLocation, failed }

class AppState with ChangeNotifier {
  final MockServiceClient _client = MockServiceClient();

  bool _initialized = false;
  bool _isMocking = false;
  LatLng? _currentLocation;
  String _currentAddress = "Move the map to select a location";
  List<LocationItem> _favorites = [];
  bool? _isMockLocationApp; // null until the native check completes
  CameraRequest? _cameraRequest;
  int _cameraToken = 0;
  String? _lastError;

  bool get initialized => _initialized;
  bool get isMocking => _isMocking;
  LatLng? get currentLocation => _currentLocation;
  String get currentAddress => _currentAddress;
  List<LocationItem> get favorites => _favorites;
  bool? get isMockLocationApp => _isMockLocationApp;
  CameraRequest? get cameraRequest => _cameraRequest;
  String? get lastError => _lastError;
  MockServiceClient get client => _client;

  /// Where the map should open: the restored/real location, or a zoomed-out
  /// world view when nothing is known yet (first launch, no permission).
  LatLng get mapStartLocation => _currentLocation ?? const LatLng(20, 0);
  double get mapStartZoom => _currentLocation == null ? 2.5 : 15.5;

  /// One-time startup: restore the last session, sync with the (possibly
  /// still running) native service, and calibrate to the device's real
  /// position when mocking is off. Called from the splash screen.
  Future<void> init() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _loadFavorites(prefs);
      final lastLat = prefs.getDouble('last_lat');
      final lastLng = prefs.getDouble('last_lng');
      if (lastLat != null && lastLng != null) {
        _currentLocation = LatLng(lastLat, lastLng);
        _currentAddress =
            prefs.getString('last_address') ?? _format(_currentLocation!);
      }

      await checkPermissions();
      _isMockLocationApp = await _client.isMockLocationApp();

      final status = await _client.getMockStatus();
      if (status.active) {
        // The service kept mocking while the app was away — reflect it.
        _isMocking = true;
        _currentLocation = LatLng(status.latitude, status.longitude);
        if (status.label.isNotEmpty) _currentAddress = status.label;
      } else {
        // Mocking is off: calibrate the map to the device's real position.
        final quick = await _lastKnownDevicePosition();
        if (quick != null) _currentLocation = quick;
        unawaited(moveToRealLocation());
      }
    } catch (_) {
      // Never block startup on a failed restore — the map falls back to
      // whatever was recovered before the failure.
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> checkPermissions() async {
    try {
      await [Permission.location, Permission.notification].request();
    } catch (_) {
      // Permission plugin unavailable (e.g. tests) — continue without.
    }
  }

  /// Re-runs the "is this the selected mock location app" check, e.g. when
  /// the user returns from Developer Settings.
  Future<void> refreshMockLocationCheck() async {
    final value = await _client.isMockLocationApp();
    if (value != _isMockLocationApp) {
      _isMockLocationApp = value;
      notifyListeners();
    }
  }

  /// Fetches the device's real position and moves the map there. Used at
  /// startup (when mocking is off) and by the my-location button.
  Future<bool> moveToRealLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (_isMocking) return false; // don't fight an active mock
      requestCamera(LatLng(position.latitude, position.longitude), zoom: 16);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<LatLng?> _lastKnownDevicePosition() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Asks the map to animate to [target]. Consumed by the home screen.
  void requestCamera(LatLng target, {double zoom = 16}) {
    _cameraRequest = CameraRequest(target, zoom, ++_cameraToken);
    notifyListeners();
  }

  void updateLocation(LatLng loc, {String? address}) {
    _currentLocation = loc;
    _currentAddress = address ?? _format(loc);
    unawaited(_persistLastLocation());

    if (_isMocking) {
      unawaited(
        _client
            .startMocking(loc.latitude, loc.longitude, label: _currentAddress)
            .catchError((_) {}),
      );
    }
    notifyListeners();
  }

  Future<void> _persistLastLocation() async {
    final loc = _currentLocation;
    if (loc == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('last_lat', loc.latitude);
    await prefs.setDouble('last_lng', loc.longitude);
    await prefs.setString('last_address', _currentAddress);
  }

  Future<MockToggleResult> toggleMocking() async {
    _lastError = null;
    if (_isMocking) {
      await _client.stopMocking();
      _isMocking = false;
      notifyListeners();
      return MockToggleResult.stopped;
    }

    final loc = _currentLocation;
    if (loc == null) return MockToggleResult.noLocation;
    if (_isMockLocationApp == false) {
      await refreshMockLocationCheck();
      if (_isMockLocationApp == false) return MockToggleResult.needsSetup;
    }

    try {
      await _client.startMocking(
        loc.latitude,
        loc.longitude,
        label: _currentAddress,
      );
      _isMocking = true;
      notifyListeners();
      return MockToggleResult.started;
    } on PlatformException catch (e) {
      _lastError = e.message ?? 'Could not start the mocking service';
      notifyListeners();
      return MockToggleResult.failed;
    }
  }

  // ---------------------------------------------------------------- favorites

  void _loadFavorites(SharedPreferences prefs) {
    final favoritesJson = prefs.getStringList('favorites') ?? [];
    _favorites = favoritesJson
        .map((item) => LocationItem.fromJson(jsonDecode(item)))
        .toList();
  }

  Future<void> addFavorite(String name) async {
    final loc = _currentLocation;
    if (loc == null) return;
    final trimmed = name.trim();
    final newItem = LocationItem(
      latitude: loc.latitude,
      longitude: loc.longitude,
      name: trimmed.isEmpty ? _currentAddress : trimmed,
      address: _currentAddress,
    );
    _favorites.add(newItem);
    await _saveFavorites();
    notifyListeners();
  }

  Future<void> removeFavorite(LocationItem item) async {
    _favorites.removeWhere((element) => element.id == item.id);
    await _saveFavorites();
    notifyListeners();
  }

  /// Re-inserts a deleted favorite at its old position (undo).
  Future<void> insertFavorite(int index, LocationItem item) async {
    _favorites.insert(index.clamp(0, _favorites.length), item);
    await _saveFavorites();
    notifyListeners();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = _favorites
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    await prefs.setStringList('favorites', favoritesJson);
  }

  // ------------------------------------------------------------------- misc

  Future<void> openSettings() async {
    await _client.openDeveloperSettings();
  }

  String _format(LatLng loc) =>
      "${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}";
}
