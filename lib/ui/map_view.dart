import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:gps_mock/models/map_style.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/control_deck.dart';
import 'package:gps_mock/ui/onboarding_dialog.dart';
import 'package:gps_mock/ui/theme.dart';
import 'package:gps_mock/ui/widgets/map_controls.dart';
import 'package:gps_mock/ui/widgets/offscreen_pin.dart';
import 'package:gps_mock/ui/widgets/place_search_bar.dart';
import 'package:gps_mock/utils/icon_raster.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:provider/provider.dart';

/// The Map tab: a full-bleed vector map with a floating search bar, a control
/// rail, a pin you drag to choose the spot, and the control deck docked to
/// the bottom.
class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => MapViewState();
}

class MapViewState extends State<MapView> with WidgetsBindingObserver {
  ml.MapLibreMapController? _mapController;

  // Camera state.
  bool _mapReady = false;
  double _bearing = 0;
  double _zoom = 15.5;
  bool _compassVisible = false;

  // Style state.
  late MapStyle _style;
  MapStyle? _appliedStyle;
  bool _threeDimensional = false;
  bool _styleBusy = false;
  Completer<void>? _styleLoadCompleter;

  // Overlays.
  String _annotationToken = '';
  final Map<String, LatLng> _favoriteCircles = {};

  // The pin is a native MapLibre annotation rather than a Flutter overlay, so
  // it stays locked to its coordinate frame-for-frame while the map moves and
  // is dragged by the renderer itself.
  static const _pinImageName = 'mock-pin';
  static const _originImageName = 'wp-origin';
  static const _destinationImageName = 'wp-destination';

  /// The marker for the fixed spot, and one per route waypoint. Both are
  /// native MapLibre symbols so they stay locked to the map as it moves.
  ml.Symbol? _pinSymbol;
  final List<ml.Symbol> _waypointSymbols = [];

  /// Which waypoint each symbol stands for, so a drag can be routed back to
  /// the right leg of the itinerary.
  final Map<String, WaypointPick> _waypointBySymbol = {};

  final Set<String> _registeredImages = {};
  bool _draggingMarker = false;
  bool _markerSyncInFlight = false;
  String _markerToken = '';

  /// Markers currently off screen, in paint order.
  List<_EdgeMarker> _edgeMarkers = const [];

  // Layout / follow state.
  double _deckHeight = 220;
  bool _followRoute = true;
  LatLng? _lastFollowedPosition;
  int _handledCameraToken = 0;
  Timer? _geocodeDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Boot on the style the last session chose, resolved against the platform
    // brightness (the app theme isn't readable this early).
    _style = MapStyle.resolve(
      context.read<AppState>().mapStyle,
      darkTheme:
          PlatformDispatcher.instance.platformBrightness == Brightness.dark,
    );
    _appliedStyle = _style;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<AppState>().isMockLocationApp == false) {
        showDialog(context: context, builder: (_) => const OnboardingDialog());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _geocodeDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AppState>().refreshMockLocationCheck();
    }
  }

  // ------------------------------------------------- shell entry points

  /// Selects [target] and flies to it. Called by the shell when a saved or
  /// historical location is chosen on another tab.
  void selectAndFly(LatLng target, String address) {
    context.read<AppState>().updateLocation(target, address: address);
    _flyTo(target, 16);
  }

  void openDirections() => context.read<AppState>().setRouteMode(true);

  // ------------------------------------------------------------- camera

  void _flyTo(LatLng target, double zoom) {
    _mapController?.animateCamera(
      ml.CameraUpdate.newLatLngZoom(_toMl(target), zoom),
    );
  }

  void _handleCameraRequest(AppState appState) {
    if (!_mapReady) return;
    final request = appState.cameraRequest;
    if (request == null || request.token == _handledCameraToken) return;
    _handledCameraToken = request.token;

    final bounds = request.bounds;
    if (bounds != null) {
      _mapController?.animateCamera(
        ml.CameraUpdate.newLatLngBounds(
          ml.LatLngBounds(
            southwest: _toMl(bounds.southWest),
            northeast: _toMl(bounds.northEast),
          ),
          left: 56,
          top: 150,
          right: 56,
          bottom: _deckHeight + 40,
        ),
      );
      return;
    }
    final target = request.target;
    if (target != null) _flyTo(target, request.zoom);
  }

  void _handleFollowRoute(AppState appState) {
    if (!_mapReady || !appState.isNavigating || !_followRoute) return;
    final position = LatLng(
      appState.mockStatus.latitude,
      appState.mockStatus.longitude,
    );
    if (position == _lastFollowedPosition) return;
    _lastFollowedPosition = position;
    _flyTo(position, math.max(_zoom, 15));
  }

  void _zoomBy(double delta) {
    final position = _mapController?.cameraPosition;
    if (position == null) return;
    HapticFeedback.selectionClick();
    _mapController?.animateCamera(
      ml.CameraUpdate.zoomTo((position.zoom + delta).clamp(1, 20)),
    );
  }

  void _resetNorth() {
    final position = _mapController?.cameraPosition;
    if (position == null) return;
    HapticFeedback.selectionClick();
    _mapController?.animateCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: position.target,
          zoom: position.zoom,
          tilt: position.tilt,
          bearing: 0,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- pin

  /// The region the off-screen indicator may sit in: the map viewport minus
  /// the search bar above and the deck below.
  Rect _mapArea(BoxConstraints constraints) {
    final top = MediaQuery.of(context).padding.top + 74;
    final bottom = constraints.maxHeight - _deckHeight - 8;
    return Rect.fromLTRB(
      0,
      top,
      constraints.maxWidth,
      math.max(top + 80, bottom),
    );
  }

  /// Registers a bitmap with the current style, once. A style load wipes
  /// registered images, so [_registeredImages] is cleared alongside it.
  Future<void> _registerImage(String name, Future<Uint8List> Function() build) async {
    if (_registeredImages.contains(name)) return;
    final controller = _mapController;
    if (controller == null) return;
    try {
      await controller.addImage(name, await build());
      _registeredImages.add(name);
    } catch (_) {
      // The style may have swapped mid-write; the next sync retries.
    }
  }

  double get _pinPixelRatio => MediaQuery.of(context).devicePixelRatio;

  Future<void> _ensureMarkerImages(AppState appState) async {
    final scheme = Theme.of(context).colorScheme;
    final status = Theme.of(context).status;
    final ratio = _pinPixelRatio;

    await _registerImage(
      _pinImageName,
      () => rasterizePin(
        color: scheme.primary,
        size: 48,
        devicePixelRatio: ratio,
      ),
    );
    await _registerImage(
      _originImageName,
      () => rasterizePin(
        color: status.origin,
        size: 48,
        devicePixelRatio: ratio,
      ),
    );
    await _registerImage(
      _destinationImageName,
      () => rasterizePin(
        color: status.destination,
        size: 48,
        devicePixelRatio: ratio,
      ),
    );
    for (var i = 0; i < appState.routeStops.length; i++) {
      await _registerImage(
        _stopImageName(i),
        () => rasterizePin(
          color: status.waypoint,
          size: 48,
          devicePixelRatio: ratio,
          label: '${i + 1}',
        ),
      );
    }
  }

  static String _stopImageName(int index) => 'wp-stop-${index + 1}';

  /// Reconciles every marker on the map: the fixed-spot pin in fixed mode, or
  /// the itinerary's green start, numbered blue stops and red destination in
  /// route mode. Cheap to call — it no-ops unless something actually changed.
  Future<void> _syncMarkers(AppState appState) async {
    final controller = _mapController;
    if (controller == null || !_mapReady || _draggingMarker) return;
    if (_markerSyncInFlight) return;

    final routeMode = appState.routeMode || appState.isNavigating;
    final token = [
      routeMode,
      appState.currentLocation,
      appState.routeOrigin,
      appState.routeDestination,
      appState.routeStops.map((stop) => stop.location).join(','),
      _registeredImages.length,
    ].join('|');
    if (token == _markerToken) return;
    _markerToken = token;

    _markerSyncInFlight = true;
    try {
      await _ensureMarkerImages(appState);
      await controller.clearSymbols();
      _pinSymbol = null;
      _waypointSymbols.clear();
      _waypointBySymbol.clear();

      if (!routeMode) {
        final pin = appState.currentLocation;
        if (pin != null) {
          _pinSymbol = await controller.addSymbol(
            ml.SymbolOptions(
              geometry: _toMl(pin),
              iconImage: _pinImageName,
              iconAnchor: 'bottom',
              iconSize: 1,
              draggable: true,
            ),
          );
        }
        return;
      }

      // Stops are added before the endpoints so the green start and red
      // destination draw on top of them where they overlap.
      for (var i = 0; i < appState.routeStops.length; i++) {
        await _addWaypointPin(
          controller,
          appState.routeStops[i].location,
          _stopImageName(i),
          WaypointPick(WaypointSlot.stop, index: i),
        );
      }
      final origin = appState.routeOrigin;
      if (origin != null) {
        await _addWaypointPin(
          controller,
          origin,
          _originImageName,
          const WaypointPick(WaypointSlot.origin),
        );
      }
      final destination = appState.routeDestination;
      if (destination != null) {
        await _addWaypointPin(
          controller,
          destination,
          _destinationImageName,
          const WaypointPick(WaypointSlot.destination),
        );
      }
    } catch (_) {
      // Retry on the next change.
      _markerToken = '';
    } finally {
      _markerSyncInFlight = false;
    }
  }

  Future<void> _addWaypointPin(
    ml.MapLibreMapController controller,
    LatLng point,
    String image,
    WaypointPick pick,
  ) async {
    final symbol = await controller.addSymbol(
      ml.SymbolOptions(
        geometry: _toMl(point),
        iconImage: image,
        iconAnchor: 'bottom',
        iconSize: 1,
        draggable: true,
      ),
    );
    _waypointSymbols.add(symbol);
    _waypointBySymbol[symbol.id] = pick;
  }

  /// MapLibre drags the annotation itself; this only records where it landed.
  void _onFeatureDrag(
    math.Point<double> point,
    ml.LatLng origin,
    ml.LatLng current,
    ml.LatLng delta,
    String id,
    ml.Annotation? annotation,
    ml.DragEventType eventType,
  ) {
    final waypoint = _waypointBySymbol[id];
    if (id != _pinSymbol?.id && waypoint == null) return;
    switch (eventType) {
      case ml.DragEventType.start:
        _draggingMarker = true;
        HapticFeedback.selectionClick();
      case ml.DragEventType.drag:
        break;
      case ml.DragEventType.end:
        _draggingMarker = false;
        HapticFeedback.mediumImpact();
        final dropped = LatLng(current.latitude, current.longitude);
        final appState = context.read<AppState>();
        if (waypoint != null) {
          _setWaypoint(appState, waypoint, dropped);
          _announce('Waypoint moved');
        } else {
          appState.updateLocation(dropped);
          _reverseGeocode(dropped);
          _announce('Pin moved');
        }
    }
  }

  void _setWaypoint(AppState appState, WaypointPick pick, LatLng point) {
    final label = '${point.latitude.toStringAsFixed(5)}, '
        '${point.longitude.toStringAsFixed(5)}';
    switch (pick.slot) {
      case WaypointSlot.origin:
        appState.setRouteOrigin(point, label);
      case WaypointSlot.destination:
        appState.setRouteDestination(point, label);
      case WaypointSlot.stop:
        appState.updateRouteStop(pick.index, point, label);
      case WaypointSlot.newStop:
        appState.addRouteStop(point, label);
    }
    _markerToken = '';
  }

  /// Tapping empty map moves the pin there — the fastest way to retarget it.
  void _onMapClick(math.Point<double> point, ml.LatLng coordinates) {
    final appState = context.read<AppState>();
    final target = LatLng(coordinates.latitude, coordinates.longitude);

    // A waypoint waiting to be placed takes the tap first.
    final pending = appState.pendingWaypointPick;
    if (pending != null) {
      HapticFeedback.mediumImpact();
      appState.applyWaypointPick(
        target,
        '${target.latitude.toStringAsFixed(5)}, '
        '${target.longitude.toStringAsFixed(5)}',
      );
      _markerToken = '';
      _announce('Waypoint set');
      unawaited(_labelWaypoint(appState, pending, target));
      return;
    }

    if (appState.isNavigating || appState.routeMode) return;
    HapticFeedback.selectionClick();
    appState.updateLocation(target);
    _reverseGeocode(target);
    _announce('Pin moved');
  }

  /// Names a waypoint placed by tapping, so the itinerary reads as a street
  /// rather than a coordinate pair once the lookup returns.
  Future<void> _labelWaypoint(
    AppState appState,
    WaypointPick pick,
    LatLng point,
  ) async {
    final address = await _lookupAddress(point);
    if (!mounted || address == null) return;
    switch (pick.slot) {
      case WaypointSlot.origin:
        if (appState.routeOrigin == point) {
          appState.setRouteOrigin(point, address);
        }
      case WaypointSlot.destination:
        if (appState.routeDestination == point) {
          appState.setRouteDestination(point, address);
        }
      case WaypointSlot.stop:
        if (pick.index < appState.routeStops.length &&
            appState.routeStops[pick.index].location == point) {
          appState.updateRouteStop(pick.index, point, address);
        }
      case WaypointSlot.newStop:
        final index = appState.routeStops.length - 1;
        if (index >= 0 && appState.routeStops[index].location == point) {
          appState.updateRouteStop(index, point, address);
        }
    }
  }

  /// Turns a coordinate into a short street-and-town label, or null when the
  /// platform geocoder has nothing to offer.
  Future<String?> _lookupAddress(LatLng point) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (placemarks.isEmpty) return null;
      final place = placemarks.first;
      final parts = [place.street, place.locality, place.country]
          .where((part) => part != null && part.isNotEmpty)
          .take(2)
          .join(', ');
      return parts.isEmpty ? null : parts;
    } catch (_) {
      // Geocoding unavailable — callers fall back to coordinates.
      return null;
    }
  }

  /// Names the coordinate so the deck can show a street rather than numbers.
  void _reverseGeocode(LatLng point) {
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 350), () async {
      final address = await _lookupAddress(point);
      if (!mounted || address == null) return;
      final appState = context.read<AppState>();
      // Only label the point the pin is still sitting on.
      if (appState.currentLocation == point) {
        appState.updateLocation(point, address: address);
      }
    });
  }

  /// Works out which markers have been panned out of view and which way they
  /// lie, so the edge pills can point back at them. Runs when the camera
  /// settles rather than every frame.
  Future<void> _updateEdgeMarkers(AppState appState) async {
    final controller = _mapController;
    if (controller == null || !_mapReady) return;

    final status = Theme.of(context).status;
    final scheme = Theme.of(context).colorScheme;
    final routeMode = appState.routeMode || appState.isNavigating;

    // Painted in list order, so later entries sit on top: stops descend, and
    // the start and destination stay above all of them.
    final candidates = <_EdgeMarker>[];
    if (routeMode) {
      for (var i = appState.routeStops.length - 1; i >= 0; i--) {
        candidates.add(
          _EdgeMarker(
            target: appState.routeStops[i].location,
            label: '${i + 1}',
            color: status.waypoint,
            onColor: Colors.white,
          ),
        );
      }
      final origin = appState.routeOrigin;
      if (origin != null) {
        candidates.add(
          _EdgeMarker(
            target: origin,
            label: 'Start',
            color: status.origin,
            onColor: Colors.white,
          ),
        );
      }
      final destination = appState.routeDestination;
      if (destination != null) {
        candidates.add(
          _EdgeMarker(
            target: destination,
            label: 'End',
            color: status.destination,
            onColor: Colors.white,
          ),
        );
      }
    } else {
      final pin = appState.currentLocation;
      if (pin != null) {
        candidates.add(
          _EdgeMarker(
            target: pin,
            label: '',
            color: scheme.primaryContainer,
            onColor: scheme.onPrimaryContainer,
          ),
        );
      }
    }

    if (candidates.isEmpty) {
      if (_edgeMarkers.isNotEmpty && mounted) {
        setState(() => _edgeMarkers = const []);
      }
      return;
    }

    try {
      final region = await controller.getVisibleRegion();
      final camera = controller.cameraPosition;
      if (!mounted || camera == null) return;

      final center = LatLng(camera.target.latitude, camera.target.longitude);
      const distance = Distance();
      final offscreen = <_EdgeMarker>[];
      for (final marker in candidates) {
        final point = marker.target;
        final inside = point.latitude >= region.southwest.latitude &&
            point.latitude <= region.northeast.latitude &&
            point.longitude >= region.southwest.longitude &&
            point.longitude <= region.northeast.longitude;
        if (inside) continue;
        // Geographic bearing, de-rotated by the map's own bearing so the
        // arrow still points the right way on a rotated map.
        final heading = distance.bearing(center, point) - camera.bearing;
        final metres = distance.as(LengthUnit.Meter, center, point);
        offscreen.add(
          marker.resolve(
            angle: heading * math.pi / 180,
            distanceLabel: metres >= 1000
                ? '${(metres / 1000).toStringAsFixed(metres >= 10000 ? 0 : 1)} km'
                : '${metres.round()} m',
          ),
        );
      }

      if (!_sameMarkers(offscreen, _edgeMarkers)) {
        setState(() => _edgeMarkers = offscreen);
      }
    } catch (_) {
      // Region unavailable — leave the pills as they were.
    }
  }

  static bool _sameMarkers(List<_EdgeMarker> a, List<_EdgeMarker> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].target != b[i].target ||
          (a[i].angle - b[i].angle).abs() > 0.01 ||
          a[i].distanceLabel != b[i].distanceLabel) {
        return false;
      }
    }
    return true;
  }

  // -------------------------------------------------------------- styles

  /// Applies [style], optionally extruding its buildings.
  Future<void> _applyStyle(MapStyle style, {bool? threeDimensional}) async {
    final controller = _mapController;
    if (controller == null || _styleBusy) return;
    final want3d = (threeDimensional ?? _threeDimensional) && style.supports3d;

    setState(() => _styleBusy = true);
    try {
      if (want3d && style.styleUrl != null) {
        await _setStyleAndWait(await _extrudeBuildings(style));
      } else {
        await _setStyleAndWait(style.style);
      }
      if (!mounted) return;
      setState(() {
        _style = style;
        _appliedStyle = style;
        _threeDimensional = want3d;
      });
      await controller.animateCamera(ml.CameraUpdate.tiltTo(want3d ? 55 : 0));
    } catch (_) {
      if (mounted) {
        setState(() {
          _style = _appliedStyle ?? style;
          _threeDimensional = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load the ${style.name} map.')),
        );
      }
    } finally {
      if (mounted) setState(() => _styleBusy = false);
    }
  }

  /// Downloads a style document and turns its flat building footprints into
  /// 3D extrusions.
  Future<String> _extrudeBuildings(MapStyle style) async {
    final response = await http
        .get(Uri.parse(style.styleUrl!))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Style returned ${response.statusCode}');
    }
    final document = jsonDecode(response.body) as Map<String, dynamic>;
    final layers = (document['layers'] as List).cast<Map<String, dynamic>>();
    final buildings = layers.firstWhere(
      (layer) => layer['id'] == 'buildings',
      orElse: () => throw StateError('Style has no buildings layer'),
    );
    buildings
      ..['type'] = 'fill-extrusion'
      ..['minzoom'] = 14
      ..['paint'] = <String, dynamic>{
        'fill-extrusion-color': style.isDark ? '#34363A' : '#C8C8C8',
        'fill-extrusion-opacity': .82,
        'fill-extrusion-height': [
          'coalesce',
          ['get', 'height'],
          12,
        ],
        'fill-extrusion-base': [
          'coalesce',
          ['get', 'min_height'],
          0,
        ],
      };
    return jsonEncode(document);
  }

  Future<void> _setStyleAndWait(String style) async {
    final controller = _mapController;
    if (controller == null) throw StateError('Map is not ready');
    _mapReady = false;
    final completer = Completer<void>();
    _styleLoadCompleter = completer;
    try {
      await controller.setStyle(style);
      await completer.future.timeout(const Duration(seconds: 20));
    } finally {
      if (identical(_styleLoadCompleter, completer)) _styleLoadCompleter = null;
    }
  }

  // --------------------------------------------------------- annotations

  /// Redraws the route line, waypoints, saved locations and the simulated
  /// position. No-ops unless something actually changed.
  Future<void> _syncAnnotations(AppState appState) async {
    final controller = _mapController;
    if (!_mapReady || controller == null) return;

    final route = appState.routePolylinePoints;
    final showRoute = appState.routeMode || appState.isNavigating;
    final status = appState.mockStatus;
    final token = [
      _style.id.name,
      _threeDimensional,
      appState.favorites.map((f) => f.id).join(','),
      showRoute,
      route?.length ?? 0,
      route?.firstOrNull,
      route?.lastOrNull,
      appState.isNavigating,
      if (appState.isNavigating) '${status.latitude},${status.longitude}',
    ].join(':');
    if (token == _annotationToken) return;
    _annotationToken = token;

    final theme = Theme.of(context);
    try {
      await controller.clearLines();
      await controller.clearCircles();
      _favoriteCircles.clear();

      if (showRoute && route != null && route.length > 1) {
        final geometry = route.map(_toMl).toList(growable: false);
        // A wide translucent casing under a solid core keeps the line legible
        // on light, dark and satellite basemaps alike.
        await controller.addLine(
          ml.LineOptions(
            geometry: geometry,
            lineColor: '#FFFFFF',
            lineWidth: 9,
            lineOpacity: .55,
          ),
        );
        await controller.addLine(
          ml.LineOptions(
            geometry: geometry,
            lineColor: _hex(theme.colorScheme.primary),
            lineWidth: 5,
            lineOpacity: .95,
          ),
        );
      }

      if (!showRoute) {
        for (final favorite in appState.favorites) {
          final circle = await controller.addCircle(
            ml.CircleOptions(
              geometry: ml.LatLng(favorite.latitude, favorite.longitude),
              circleRadius: 7,
              circleColor: _hex(theme.colorScheme.tertiary),
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 2,
            ),
          );
          _favoriteCircles[circle.id] =
              LatLng(favorite.latitude, favorite.longitude);
        }
      }

      if (appState.isNavigating) {
        await controller.addCircle(
          ml.CircleOptions(
            geometry: ml.LatLng(status.latitude, status.longitude),
            circleRadius: 9,
            circleColor: _hex(theme.colorScheme.primary),
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 3,
          ),
        );
      }
    } catch (_) {
      // The style may have swapped mid-write; retry on the next change.
      _annotationToken = '';
    }
  }

  static ml.LatLng _toMl(LatLng point) =>
      ml.LatLng(point.latitude, point.longitude);

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // "Auto" tracks the app theme; an explicit choice is honoured as-is.
    final wanted = MapStyle.resolve(appState.mapStyle, darkTheme: isDark);
    if (_mapReady &&
        !_styleBusy &&
        (_appliedStyle == null || _appliedStyle!.style != wanted.style)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyStyle(wanted);
      });
    }

    _handleCameraRequest(appState);
    _handleFollowRoute(appState);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncAnnotations(appState);
      _syncMarkers(appState);
    });

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              ml.MapLibreMap(
                key: const ValueKey('gps-mock-map'),
                styleString: _style.style,
                initialCameraPosition: ml.CameraPosition(
                  target: _toMl(appState.mapStartLocation),
                  zoom: appState.mapStartZoom,
                ),
                minMaxZoomPreference: const ml.MinMaxZoomPreference(1, 20),
                // Required for cameraPosition to be readable — without it the
                // zoom and compass controls have nothing to act on.
                trackCameraPosition: true,
                compassEnabled: false,
                myLocationEnabled: false,
                onMapCreated: (controller) {
                  _mapController = controller;
                  controller.onCircleTapped.add(_onCircleTapped);
                  controller.onFeatureDrag.add(_onFeatureDrag);
                },
                onStyleLoadedCallback: () async {
                  final state = context.read<AppState>();
                  // A style load wipes registered images and annotations.
                  _annotationToken = '';
                  _markerToken = '';
                  _pinSymbol = null;
                  _waypointSymbols.clear();
                  _waypointBySymbol.clear();
                  _registeredImages.clear();
                  final completer = _styleLoadCompleter;
                  if (completer != null && !completer.isCompleted) {
                    completer.complete();
                  }
                  if (mounted) setState(() => _mapReady = true);
                  if (!mounted) return;
                  _syncAnnotations(state);
                  await _syncMarkers(state);
                  if (mounted) _updateEdgeMarkers(state);
                },
                onCameraMove: (position) {
                  // Runs every frame of a pan: keep it to bookkeeping. The
                  // pin is a native annotation, so it needs nothing here.
                  _zoom = position.zoom;
                  final rotated = (_bearing - position.bearing).abs() > 2;
                  if (rotated != _compassVisible) {
                    setState(() {
                      _bearing = position.bearing;
                      _compassVisible = rotated;
                    });
                  } else if (rotated) {
                    setState(() => _bearing = position.bearing);
                  }
                },
                onCameraIdle: () {
                  final camera = _mapController?.cameraPosition;
                  if (camera != null && _bearing != camera.bearing) {
                    setState(() => _bearing = camera.bearing);
                  }
                  _updateEdgeMarkers(context.read<AppState>());
                },
                onMapClick: _onMapClick,
                onMapLongClick: (point, coordinates) => _onLongPress(
                  LatLng(coordinates.latitude, coordinates.longitude),
                ),
              ),
              for (final marker in _edgeMarkers)
                OffscreenPinIndicator(
                  key: ValueKey(marker.target),
                  area: _mapArea(constraints),
                  angle: marker.angle,
                  label: marker.label,
                  distanceLabel: marker.distanceLabel,
                  color: marker.color,
                  onColor: marker.onColor,
                  onTap: () => _flyTo(marker.target, math.max(_zoom, 15)),
                ),
              _buildTopBar(context, appState),
              _buildControlRail(context, appState),
              if (appState.pendingWaypointPick != null)
                _buildPickPrompt(context, appState, constraints),
              Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAttribution(context),
                    RepaintBoundary(
                      child: ControlDeck(onHeightChanged: _onDeckHeight),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onDeckHeight(double height) {
    if ((height - _deckHeight).abs() < 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _deckHeight = height);
    });
  }

  // ------------------------------------------------------ map interaction

  void _onCircleTapped(ml.Circle circle) {
    final point = _favoriteCircles[circle.id];
    if (point == null) return;
    final appState = context.read<AppState>();
    final favorite = appState.favorites.firstWhere(
      (item) =>
          item.latitude == point.latitude && item.longitude == point.longitude,
      orElse: () => appState.favorites.first,
    );
    HapticFeedback.selectionClick();
    appState.updateLocation(point, address: favorite.name);
    _flyTo(point, math.max(_zoom, 16));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Selected "${favorite.name}"')),
    );
  }

  /// Long-pressing the map moves the pin straight there.
  void _onLongPress(LatLng point) {
    final appState = context.read<AppState>();
    if (appState.isNavigating) return;
    HapticFeedback.mediumImpact();
    appState.updateLocation(point);
    _reverseGeocode(point);
    _announce('Pin moved');
  }

  // -------------------------------------------------------------- top bar

  Widget _buildTopBar(BuildContext context, AppState appState) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 12,
      right: 12,
      child: RepaintBoundary(
        child: Column(
          children: [
            PlaceSearchBar(
              onSelected: (place) {
                appState.updateLocation(place.location, address: place.label);
                _flyTo(place.location, 16);
              },
            ),
            if (appState.isMockLocationApp == false) ...[
              const SizedBox(height: 10),
              _buildSetupBanner(context),
            ],
            if (appState.isMocking) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _LiveBadge(navigating: appState.isNavigating),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSetupBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showDialog(
          context: context,
          builder: (_) => const OnboardingDialog(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: scheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Not set as the mock location app — tap to fix',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: scheme.onErrorContainer,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------- control rail

  Widget _buildControlRail(BuildContext context, AppState appState) {
    final showCompass = _compassVisible || _bearing.abs() > 1;
    // Clear the search bar plus any banner/badge stacked beneath it.
    final topInset = MediaQuery.of(context).padding.top +
        78 +
        (appState.isMockLocationApp == false ? 66 : 0) +
        (appState.isMocking ? 46 : 0);

    return Positioned(
      right: 12,
      top: topInset,
      child: RepaintBoundary(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (showCompass) ...[
              MapControlGroup(
                children: [
                  MapControlButton(
                    tooltip: 'Reset to north',
                    onPressed: _resetNorth,
                    child: Transform.rotate(
                      angle: -_bearing * math.pi / 180,
                      child: const Icon(Icons.explore_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            MapControlGroup(
              children: [
                MapControlButton(
                  tooltip: 'Zoom in',
                  onPressed: () => _zoomBy(1),
                  child: const Icon(Icons.add),
                ),
                const MapControlDivider(),
                MapControlButton(
                  tooltip: 'Zoom out',
                  onPressed: () => _zoomBy(-1),
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
            const SizedBox(height: 10),
            MapControlGroup(
              children: [
                MapControlButton(
                  tooltip: 'Map style',
                  onPressed: () => _openStylePicker(context, appState),
                  child: const Icon(Icons.layers_outlined),
                ),
                if (_style.supports3d) ...[
                  const MapControlDivider(),
                  MapControlButton(
                    tooltip: _threeDimensional
                        ? 'Turn off 3D buildings'
                        : 'Show 3D buildings',
                    highlighted: _threeDimensional,
                    onPressed: _styleBusy
                        ? null
                        : () => _applyStyle(
                              _style,
                              threeDimensional: !_threeDimensional,
                            ),
                    child: _styleBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.domain_outlined),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            if (appState.isNavigating) ...[
              MapControlGroup(
                children: [
                  MapControlButton(
                    tooltip: _followRoute
                        ? 'Stop following the simulated position'
                        : 'Follow the simulated position',
                    highlighted: _followRoute,
                    onPressed: () => setState(() {
                      _followRoute = !_followRoute;
                      _lastFollowedPosition = null;
                    }),
                    child: const Icon(Icons.navigation_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            MapControlGroup(
              children: [
                MapControlButton(
                  tooltip: 'Go to my real location',
                  onPressed: () => _goToMyLocation(context),
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The banner shown while a waypoint is waiting to be placed by tapping the
  /// map. It sits just above the deck, where the itinerary row that armed it
  /// is still visible.
  Widget _buildPickPrompt(
    BuildContext context,
    AppState appState,
    BoxConstraints constraints,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final pending = appState.pendingWaypointPick!;
    return Positioned(
      left: 12,
      right: 12,
      bottom: _deckHeight + 12,
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 20,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  pending.prompt,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: appState.cancelWaypointPick,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttribution(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 4),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: .62),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            child: Text(
              _style.attribution,
              style: TextStyle(
                fontSize: 9,
                color: scheme.onSurface.withValues(alpha: .75),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- actions

  Future<void> _openStylePicker(BuildContext context, AppState appState) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Map style',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            RadioGroup<MapStyleId>(
              groupValue: appState.mapStyle,
              onChanged: (value) {
                if (value == null) return;
                appState.setMapStyle(value);
                Navigator.pop(sheetContext);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final style in MapStyle.all)
                    RadioListTile<MapStyleId>(
                      value: style.id,
                      title: Text(style.name),
                      subtitle: Text(style.description),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _goToMyLocation(BuildContext context) async {
    final moved = await context.read<AppState>().moveToRealLocation();
    if (moved || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not get your location. Check that location is on and '
          'permission is granted.',
        ),
      ),
    );
  }

  void _announce(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.navigating});

  final bool navigating;

  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).status;
    return Semantics(
      liveRegion: true,
      label: navigating ? 'Route simulation active' : 'Location mocking active',
      child: Material(
        color: status.live,
        borderRadius: BorderRadius.circular(20),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                navigating ? Icons.route : Icons.gps_fixed,
                size: 14,
                color: status.onLive,
              ),
              const SizedBox(width: 7),
              Text(
                navigating ? 'SIMULATING ROUTE' : 'MOCKING',
                style: TextStyle(
                  color: status.onLive,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A marker that has been panned out of view, with where it lies once the
/// camera has been consulted.
class _EdgeMarker {
  const _EdgeMarker({
    required this.target,
    required this.label,
    required this.color,
    required this.onColor,
    this.angle = 0,
    this.distanceLabel = '',
  });

  final LatLng target;

  /// Short badge text: a stop number, "Start", "End", or empty for the
  /// fixed-spot pin.
  final String label;
  final Color color;
  final Color onColor;
  final double angle;
  final String distanceLabel;

  _EdgeMarker resolve({required double angle, required String distanceLabel}) {
    return _EdgeMarker(
      target: target,
      label: label,
      color: color,
      onColor: onColor,
      angle: angle,
      distanceLabel: distanceLabel,
    );
  }
}
