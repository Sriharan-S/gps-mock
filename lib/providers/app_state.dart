import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/models/map_style.dart';
import 'package:gps_mock/models/mock_history_entry.dart';
import 'package:gps_mock/services/mock_service_client.dart';
import 'package:gps_mock/services/route_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A geographic box the map can be asked to fit. Kept local so the state
/// layer doesn't depend on a map rendering package.
class GeoBounds {
  const GeoBounds(this.southWest, this.northEast);

  final LatLng southWest;
  final LatLng northEast;

  factory GeoBounds.fromPoints(List<LatLng> points) {
    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    return GeoBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }
}

/// The area a simulated trip covered, kept so it can later be downloaded for
/// offline use without having to re-plan the route.
class RouteArea {
  const RouteArea(this.label, this.southWest, this.northEast);

  final String label;
  final LatLng southWest;
  final LatLng northEast;

  Map<String, dynamic> toJson() => {
        'label': label,
        'swLat': southWest.latitude,
        'swLng': southWest.longitude,
        'neLat': northEast.latitude,
        'neLng': northEast.longitude,
      };

  factory RouteArea.fromJson(Map<String, dynamic> json) => RouteArea(
        json['label'] as String? ?? 'Route',
        LatLng(
          (json['swLat'] as num).toDouble(),
          (json['swLng'] as num).toDouble(),
        ),
        LatLng(
          (json['neLat'] as num).toDouble(),
          (json['neLng'] as num).toDouble(),
        ),
      );
}

/// Which leg of the itinerary a map tap should fill in.
enum WaypointSlot { origin, stop, destination, newStop }

/// A waypoint waiting to be placed by tapping the map.
class WaypointPick {
  const WaypointPick(this.slot, {this.index = 0});

  final WaypointSlot slot;

  /// Which stop, when [slot] is [WaypointSlot.stop].
  final int index;

  String get prompt => switch (slot) {
        WaypointSlot.origin => 'Tap the map to set the start point',
        WaypointSlot.destination => 'Tap the map to set the destination',
        WaypointSlot.stop => 'Tap the map to move stop ${index + 1}',
        WaypointSlot.newStop => 'Tap the map to add a stop',
      };
}

/// An intermediate stop on a planned mock route.
class RouteStop {
  final LatLng location;
  final String label;
  const RouteStop(this.location, this.label);
}

/// A one-shot request asking the map to move its camera. The home screen
/// tracks the token so each request is animated exactly once. Either a
/// [target] point or [bounds] to fit is set.
class CameraRequest {
  final LatLng? target;
  final double zoom;
  final GeoBounds? bounds;
  final int token;
  const CameraRequest(this.token, {this.target, this.zoom = 16, this.bounds});
}

enum MockToggleResult { started, stopped, needsSetup, noLocation, failed }

class AppState with ChangeNotifier {
  final MockServiceClient _client = MockServiceClient();
  final RouteService _routeService = RouteService();

  bool _initialized = false;
  bool _isMocking = false;
  LatLng? _currentLocation;
  /// Shown until a real location has been picked or reverse-geocoded.
  static const _addressPlaceholder = 'Drag the pin to choose a spot';

  String _currentAddress = _addressPlaceholder;
  List<LocationItem> _favorites = [];
  bool? _isMockLocationApp; // null until the native check completes
  CameraRequest? _cameraRequest;
  int _cameraToken = 0;
  String? _lastError;

  // Route planning (mock navigation)
  bool _routeMode = false;
  LatLng? _routeOrigin;
  String _routeOriginLabel = '';
  LatLng? _routeDestination;
  String _routeDestinationLabel = '';
  final List<RouteStop> _routeStops = [];
  RouteResult? _plannedRoute;
  bool _fetchingRoute = false;
  String? _routeError;

  // UI-level state shared across tabs
  MapStyleId _mapStyle = MapStyleId.auto;
  ThemeMode _themeMode = ThemeMode.system;
  List<String> _recentSearches = [];
  List<RouteArea> _routeAreas = [];
  List<MockHistoryEntry> _history = [];

  // Live service status (polled once per second while the app is open)
  MockStatus _mockStatus = MockStatus.inactive;
  Timer? _statusTimer;
  bool _reloadingActiveRoute = false;
  List<LatLng>? _activeRoutePoints;
  DateTime _ignoreInactiveUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _handledRouteHandoff = false;
  WaypointPick? _pendingWaypointPick;

  bool get initialized => _initialized;
  bool get isMocking => _isMocking;
  LatLng? get currentLocation => _currentLocation;
  String get currentAddress => _currentAddress;

  /// Whether the pin has a real label rather than the "drag me" placeholder.
  bool get hasNamedLocation => _currentAddress != _addressPlaceholder;
  List<LocationItem> get favorites => _favorites;
  bool? get isMockLocationApp => _isMockLocationApp;
  CameraRequest? get cameraRequest => _cameraRequest;
  String? get lastError => _lastError;
  MockServiceClient get client => _client;

  bool get routeMode => _routeMode;
  LatLng? get routeOrigin => _routeOrigin;
  String get routeOriginLabel => _routeOriginLabel;
  LatLng? get routeDestination => _routeDestination;
  String get routeDestinationLabel => _routeDestinationLabel;
  List<RouteStop> get routeStops => List.unmodifiable(_routeStops);
  RouteResult? get plannedRoute => _plannedRoute;
  bool get fetchingRoute => _fetchingRoute;
  String? get routeError => _routeError;
  MapStyleId get mapStyle => _mapStyle;
  ThemeMode get themeMode => _themeMode;
  List<String> get recentSearches => List.unmodifiable(_recentSearches);
  List<RouteArea> get routeAreas => List.unmodifiable(_routeAreas);
  WaypointPick? get pendingWaypointPick => _pendingWaypointPick;
  List<MockHistoryEntry> get history => _history;

  /// Switches the bottom panel between Fixed and Route mode. When entering
  /// route mode with no origin yet, defaults it to the current pin.
  void setRouteMode(bool value) {
    if (_routeMode == value) return;
    _routeMode = value;
    _pendingWaypointPick = null;
    if (value && _routeOrigin == null && _currentLocation != null) {
      _routeOrigin = _currentLocation;
      // The placeholder is an instruction, not a place name — fall back to
      // coordinates until the pin has a real label.
      _routeOriginLabel = _currentAddress == _addressPlaceholder
          ? _format(_currentLocation!)
          : _currentAddress;
    }
    notifyListeners();
  }

  Future<void> setMapStyle(MapStyleId style) async {
    if (_mapStyle == style) return;
    _mapStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('map_style', style.name);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  /// Remembers a search term so the search sheet can offer it again. Most
  /// recent first, de-duplicated, capped at six.
  Future<void> rememberSearch(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    _recentSearches
      ..removeWhere((item) => item.toLowerCase() == trimmed.toLowerCase())
      ..insert(0, trimmed);
    if (_recentSearches.length > 6) {
      _recentSearches = _recentSearches.sublist(0, 6);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_searches', _recentSearches);
  }

  Future<void> clearRecentSearches() async {
    _recentSearches = [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_searches');
  }

  MockStatus get mockStatus => _mockStatus;
  bool get isNavigating => _mockStatus.active && _mockStatus.mode == 'route';

  /// Points to draw on the map: the planned route, or the active route
  /// reloaded from disk after an app restart mid-navigation.
  List<LatLng>? get routePolylinePoints =>
      _plannedRoute?.points ?? _activeRoutePoints;

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
      unawaited(_syncFavoritesToNative());
      _mapStyle = MapStyleId.values.asNameMap()[prefs.getString('map_style')] ??
          MapStyleId.auto;
      _themeMode = ThemeMode.values.asNameMap()[prefs.getString('theme_mode')] ??
          ThemeMode.system;
      _recentSearches = prefs.getStringList('recent_searches') ?? [];
      _routeAreas = (prefs.getStringList('route_areas') ?? [])
          .map((item) => RouteArea.fromJson(jsonDecode(item)))
          .toList();
      unawaited(loadHistory());
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
        _mockStatus = status;
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
      _startStatusPolling();
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
  /// startup (when mocking is off) and by the my-location button. Requests
  /// the permission itself if needed and falls back to the last known fix
  /// when a fresh one can't be obtained in time.
  Future<bool> moveToRealLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return false;

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return false;
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
    _cameraRequest = CameraRequest(++_cameraToken, target: target, zoom: zoom);
    notifyListeners();
  }

  /// Asks the map to fit [bounds] (e.g. a whole planned route).
  void requestCameraBounds(GeoBounds bounds) {
    _cameraRequest = CameraRequest(++_cameraToken, bounds: bounds);
    notifyListeners();
  }

  void updateLocation(LatLng loc, {String? address}) {
    _currentLocation = loc;
    _currentAddress = address ?? _format(loc);
    unawaited(_persistLastLocation());

    // Retarget a running fixed mock; never silently replace a running
    // route simulation just because the pin moved.
    if (_isMocking && !isNavigating) {
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
      _mockStatus = MockStatus.inactive;
      _activeRoutePoints = null;
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
      _ignoreInactiveUntil = DateTime.now().add(const Duration(seconds: 3));
      notifyListeners();
      return MockToggleResult.started;
    } on PlatformException catch (e) {
      _lastError = e.message ?? 'Could not start the mocking service';
      notifyListeners();
      return MockToggleResult.failed;
    }
  }

  // ------------------------------------------------------- waypoint picking

  /// Arms a waypoint so the next map tap places it.
  void armWaypointPick(WaypointSlot slot, {int index = 0}) {
    _pendingWaypointPick = WaypointPick(slot, index: index);
    notifyListeners();
  }

  void cancelWaypointPick() {
    if (_pendingWaypointPick == null) return;
    _pendingWaypointPick = null;
    notifyListeners();
  }

  /// Fills the armed waypoint from a map tap. Returns false when nothing was
  /// waiting, so the caller can fall back to its normal tap behaviour.
  bool applyWaypointPick(LatLng location, String label) {
    final pending = _pendingWaypointPick;
    if (pending == null) return false;
    _pendingWaypointPick = null;
    switch (pending.slot) {
      case WaypointSlot.origin:
        setRouteOrigin(location, label);
      case WaypointSlot.destination:
        setRouteDestination(location, label);
      case WaypointSlot.stop:
        updateRouteStop(pending.index, location, label);
      case WaypointSlot.newStop:
        addRouteStop(location, label);
    }
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------- mock navigation

  void setRouteOrigin(LatLng location, String label) {
    _routeOrigin = location;
    _routeOriginLabel = label;
    unawaited(_fetchPlannedRoute());
  }

  void setRouteDestination(LatLng location, String label) {
    _routeDestination = location;
    _routeDestinationLabel = label;
    unawaited(_fetchPlannedRoute());
  }

  void swapRouteEndpoints() {
    final location = _routeOrigin;
    final label = _routeOriginLabel;
    _routeOrigin = _routeDestination;
    _routeOriginLabel = _routeDestinationLabel;
    _routeDestination = location;
    _routeDestinationLabel = label;
    // Reversing the trip also reverses the order of intermediate stops.
    final reversed = _routeStops.reversed.toList();
    _routeStops
      ..clear()
      ..addAll(reversed);
    unawaited(_fetchPlannedRoute());
  }

  void addRouteStop(LatLng location, String label) {
    _routeStops.add(RouteStop(location, label));
    unawaited(_fetchPlannedRoute());
  }

  void updateRouteStop(int index, LatLng location, String label) {
    if (index < 0 || index >= _routeStops.length) return;
    _routeStops[index] = RouteStop(location, label);
    unawaited(_fetchPlannedRoute());
  }

  void removeRouteStop(int index) {
    if (index < 0 || index >= _routeStops.length) return;
    _routeStops.removeAt(index);
    unawaited(_fetchPlannedRoute());
  }

  void clearRoute() {
    _routeOrigin = null;
    _routeOriginLabel = '';
    _routeDestination = null;
    _routeDestinationLabel = '';
    _routeStops.clear();
    _plannedRoute = null;
    _routeError = null;
    _fetchingRoute = false;
    notifyListeners();
  }

  void retryRouteFetch() => unawaited(_fetchPlannedRoute());

  List<LatLng> get _plannedWaypoints => [
        if (_routeOrigin != null) _routeOrigin!,
        ..._routeStops.map((stop) => stop.location),
        if (_routeDestination != null) _routeDestination!,
      ];

  Future<void> _fetchPlannedRoute() async {
    _plannedRoute = null;
    _routeError = null;
    if (_routeOrigin == null || _routeDestination == null) {
      notifyListeners();
      return;
    }
    final waypoints = _plannedWaypoints;

    _fetchingRoute = true;
    notifyListeners();
    try {
      final route = await _routeService.fetchRoute(waypoints);
      // Ignore stale responses if the endpoints changed mid-fetch.
      if (!listEquals(waypoints, _plannedWaypoints)) return;
      _plannedRoute = route;
      requestCameraBounds(GeoBounds.fromPoints(route.points));
    } on RouteException catch (e) {
      _routeError = e.message;
    } catch (_) {
      _routeError = 'Could not calculate the route.';
    } finally {
      _fetchingRoute = false;
      notifyListeners();
    }
  }

  /// Starts simulating movement along the planned route, finishing in
  /// [durationMinutes]. The simulation runs in the native foreground service
  /// so it survives the app being closed.
  Future<MockToggleResult> startNavigation(int durationMinutes) async {
    _lastError = null;
    final route = _plannedRoute;
    if (route == null) return MockToggleResult.noLocation;
    if (durationMinutes <= 0) {
      _lastError = 'Duration must be at least 1 minute';
      notifyListeners();
      return MockToggleResult.failed;
    }
    if (_isMockLocationApp == false) {
      await refreshMockLocationCheck();
      if (_isMockLocationApp == false) return MockToggleResult.needsSetup;
    }

    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/mock_route.json');
      final data = route.points
          .map((p) => [p.latitude, p.longitude])
          .toList(growable: false);
      await file.writeAsString(jsonEncode(data));

      final from = _routeOriginLabel.isEmpty ? 'Start' : _routeOriginLabel;
      final to = _routeDestinationLabel.isEmpty
          ? 'Destination'
          : _routeDestinationLabel;
      final stops = _routeStops.isEmpty
          ? ''
          : ' (+${_routeStops.length} stop${_routeStops.length == 1 ? '' : 's'})';
      await _client.startRoute(
        routeFilePath: file.path,
        durationSeconds: durationMinutes * 60,
        label: '$from → $to$stops',
        fromLabel: from,
        toLabel: to,
        distanceMeters: route.distanceMeters,
        stopsJson: jsonEncode(_notificationStops(route)),
      );
      _isMocking = true;
      _ignoreInactiveUntil = DateTime.now().add(const Duration(seconds: 3));
      notifyListeners();
      unawaited(_maybeRequestBatteryExemption());
      unawaited(_rememberRouteArea('$from → $to', route.points));
      return MockToggleResult.started;
    } on PlatformException catch (e) {
      _lastError = e.message ?? 'Could not start the route simulation';
      notifyListeners();
      return MockToggleResult.failed;
    } catch (_) {
      _lastError = 'Could not start the route simulation';
      notifyListeners();
      return MockToggleResult.failed;
    }
  }

  /// Keeps the last few route corridors so they can be offered as offline
  /// download areas later.
  Future<void> _rememberRouteArea(String label, List<LatLng> points) async {
    if (points.isEmpty) return;
    final bounds = GeoBounds.fromPoints(points);
    _routeAreas
      ..removeWhere((area) => area.label == label)
      ..insert(0, RouteArea(label, bounds.southWest, bounds.northEast));
    if (_routeAreas.length > 5) _routeAreas = _routeAreas.sublist(0, 5);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'route_areas',
      _routeAreas.map((area) => jsonEncode(area.toJson())).toList(),
    );
  }

  List<Map<String, Object>> _notificationStops(RouteResult route) {
    if (_routeStops.isEmpty || route.points.length < 2) return const [];
    const distance = Distance();
    final cumulative = List<double>.filled(route.points.length, 0);
    for (var i = 1; i < route.points.length; i++) {
      cumulative[i] = cumulative[i - 1] +
          distance.as(
            LengthUnit.Meter,
            route.points[i - 1],
            route.points[i],
          );
    }
    final total = cumulative.last;
    return _routeStops.map((stop) {
      var nearest = 0;
      var nearestMeters = double.infinity;
      for (var i = 0; i < route.points.length; i++) {
        final meters = distance.as(
          LengthUnit.Meter,
          stop.location,
          route.points[i],
        );
        if (meters < nearestMeters) {
          nearestMeters = meters;
          nearest = i;
        }
      }
      return <String, Object>{
        'label': stop.label.isEmpty ? 'Stop' : stop.label,
        'progress': total == 0 ? 0.0 : cumulative[nearest] / total,
      };
    }).toList(growable: false);
  }

  Future<void> stopNavigation() async {
    await _client.stopMocking();
    _isMocking = false;
    _mockStatus = MockStatus.inactive;
    _activeRoutePoints = null;
    notifyListeners();
  }

  /// Long route simulations die if the system puts the app to sleep — ask
  /// for the battery-optimization exemption once, on the first route start.
  Future<void> _maybeRequestBatteryExemption() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('asked_battery_exemption') == true) return;
      await prefs.setBool('asked_battery_exemption', true);
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {
      // The setup sheet offers this again manually.
    }
  }

  // --------------------------------------------------------------- history

  /// Loads past mock sessions recorded by the native service (covers
  /// sessions started from tiles/widgets too). Newest first.
  Future<void> loadHistory() async {
    try {
      final raw = await _client.getHistoryJson();
      final data = jsonDecode(raw) as List;
      _history = data
          .map((item) =>
              MockHistoryEntry.fromJson((item as Map).cast<String, dynamic>()))
          .toList()
          .reversed
          .toList();
      notifyListeners();
    } catch (_) {
      // Keep the previous list.
    }
  }

  Future<void> clearHistory() async {
    await _client.clearHistory();
    _history = [];
    notifyListeners();
  }

  // -------------------------------------------------------- status polling

  void _startStatusPolling() {
    _statusTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_pollStatus()),
    );
  }

  /// Keeps the UI in sync with the native service — covers route progress,
  /// the notification Stop button, and quick-settings tiles/widgets changing
  /// the mock while the app is open.
  Future<void> _pollStatus() async {
    final status = await _client.getMockStatus();

    // Right after a start call the service may not have published its status
    // yet — don't let one stale "inactive" reading flicker the UI.
    if (!status.active && DateTime.now().isBefore(_ignoreInactiveUntil)) {
      return;
    }

    final changed = status.active != _mockStatus.active ||
        status.mode != _mockStatus.mode ||
        status.latitude != _mockStatus.latitude ||
        status.longitude != _mockStatus.longitude ||
        status.remainingSeconds != _mockStatus.remainingSeconds ||
        status.arrived != _mockStatus.arrived ||
        status.active != _isMocking;

    final wasMocking = _isMocking;
    _mockStatus = status;
    _isMocking = status.active;

    // A session started or ended (possibly from a tile/widget/notification):
    // refresh the recorded history.
    if (wasMocking != status.active) unawaited(loadHistory());

    // The route simulation reached its destination and the service handed
    // over to a fixed mock parked there: leave route mode and follow the pin
    // to the destination so the UI matches what is actually being mocked.
    if (status.active &&
        status.mode == 'fixed' &&
        status.arrivedFromRoute &&
        !_handledRouteHandoff) {
      _handledRouteHandoff = true;
      _routeMode = false;
      _activeRoutePoints = null;
      _plannedRoute = null;
      final destination = LatLng(status.latitude, status.longitude);
      _currentLocation = destination;
      if (status.label.isNotEmpty) _currentAddress = status.label;
      requestCamera(destination, zoom: 16);
      unawaited(_persistLastLocation());
      notifyListeners();
    }
    if (!status.arrivedFromRoute) _handledRouteHandoff = false;

    // A fixed mock started outside the app (quick-settings tile, widget)
    // while the UI is open: move the pin to what is actually being mocked.
    if (!wasMocking && status.active && status.mode == 'fixed') {
      final serviceLocation = LatLng(status.latitude, status.longitude);
      if (serviceLocation != _currentLocation) {
        _currentLocation = serviceLocation;
        if (status.label.isNotEmpty) _currentAddress = status.label;
        requestCamera(serviceLocation, zoom: 16);
      }
    }
    if (!status.active) {
      _activeRoutePoints = null;
    } else if (isNavigating &&
        _plannedRoute == null &&
        _activeRoutePoints == null) {
      unawaited(_reloadActiveRoute(status.routeFile));
    }
    if (changed) notifyListeners();
  }

  /// Redraws the active route polyline after an app restart mid-navigation.
  Future<void> _reloadActiveRoute(String? path) async {
    if (path == null || _reloadingActiveRoute) return;
    _reloadingActiveRoute = true;
    try {
      final raw = await File(path).readAsString();
      final data = jsonDecode(raw) as List;
      _activeRoutePoints = data
          .map<LatLng>(
            (p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          )
          .toList();
      notifyListeners();
    } catch (_) {
      // File gone — navigation still works, just without the polyline.
    } finally {
      _reloadingActiveRoute = false;
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
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

  /// Starts mocking [item] directly from a list, without a trip through the
  /// map. Retargets an already-running fixed mock rather than stopping it.
  Future<MockToggleResult> mockFavoriteNow(LocationItem item) async {
    final point = LatLng(item.latitude, item.longitude);
    updateLocation(point, address: item.name);
    requestCamera(point, zoom: 16);
    if (_isMocking && !isNavigating) return MockToggleResult.started;
    if (isNavigating) await stopNavigation();
    return toggleMocking();
  }

  Future<void> renameFavorite(LocationItem item, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final index = _favorites.indexWhere((element) => element.id == item.id);
    if (index < 0) return;
    _favorites[index] = LocationItem(
      id: item.id,
      latitude: item.latitude,
      longitude: item.longitude,
      name: trimmed,
      address: item.address,
    );
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
    final favoritesJson =
        _favorites.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList('favorites', favoritesJson);
    unawaited(_syncFavoritesToNative());
  }

  /// Mirrors favorites into native storage so quick-settings tiles and
  /// home-screen widgets can use them without the Flutter engine running.
  Future<void> _syncFavoritesToNative() async {
    final json = jsonEncode(
      _favorites.map((item) => item.toJson()).toList(growable: false),
    );
    await _client.syncFavorites(json);
  }

  // ------------------------------------------------------------------- misc

  Future<void> openSettings() async {
    await _client.openDeveloperSettings();
  }

  String _format(LatLng loc) =>
      "${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}";
}
