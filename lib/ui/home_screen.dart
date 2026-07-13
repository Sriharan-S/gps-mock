import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:geocoding/geocoding.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/services/search_service.dart';
import 'package:gps_mock/ui/favorites_sheet.dart';
import 'package:gps_mock/ui/onboarding_dialog.dart';
import 'package:gps_mock/ui/route_panel.dart';
import 'package:gps_mock/ui/save_favorite_dialog.dart';
import 'package:gps_mock/utils/constants.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// Color matrix that turns the standard OSM tiles into a dark map: inverted
/// grayscale, so streets stay readable while the background goes dark.
const List<double> _darkTileMatrix = <double>[
  -0.2126, -0.7152, -0.0722, 0, 255, //
  -0.2126, -0.7152, -0.0722, 0, 255, //
  -0.2126, -0.7152, -0.0722, 0, 255, //
  0, 0, 0, 1, 0, //
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimatedMapController _mapController = AnimatedMapController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    curve: Curves.easeInOut,
  );
  final SearchService _searchService = SearchService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _idleDebounce;
  int _handledCameraToken = 0;
  String _lastSearchQuery = '';
  bool _routeMode = false;
  bool _followRoute = true;
  LatLng? _lastFollowedPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only nag about Developer Options when the app is genuinely not set
      // as the mock location app (checked natively during startup).
      if (mounted && context.read<AppState>().isMockLocationApp == false) {
        showDialog(context: context, builder: (_) => const OnboardingDialog());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleDebounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // The user may have just enabled us in Developer Settings.
      context.read<AppState>().refreshMockLocationCheck();
    }
  }

  // ----------------------------------------------------------- map camera

  /// Executes pending one-shot camera requests coming from the app state
  /// (startup calibration, search selection, favorites, my-location,
  /// route-fit).
  void _handleCameraRequest(AppState appState) {
    final request = appState.cameraRequest;
    if (request == null || request.token == _handledCameraToken) return;
    _handledCameraToken = request.token;
    final bounds = request.bounds;
    final target = request.target;
    if (bounds != null) {
      _mapController.animatedFitCamera(
        cameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60),
        ),
      );
    } else if (target != null) {
      _mapController.animateTo(dest: target, zoom: request.zoom);
    }
  }

  /// While navigating with camera-follow enabled, tracks the moving mock
  /// position.
  void _handleFollowRoute(AppState appState) {
    if (!appState.isNavigating || !_followRoute) return;
    final position = LatLng(
      appState.mockStatus.latitude,
      appState.mockStatus.longitude,
    );
    if (position == _lastFollowedPosition) return;
    _lastFollowedPosition = position;
    _mapController.animateTo(dest: position);
  }

  /// Debounced "camera idle": reverse-geocodes the map center once panning
  /// or zooming settles, mirroring the old behavior.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _idleDebounce?.cancel();
    _idleDebounce = Timer(const Duration(milliseconds: 500), () {
      _onCameraIdle(camera.center);
    });
  }

  Future<void> _onCameraIdle(LatLng center) async {
    if (!mounted) return;
    // While a route simulation runs the camera follows the moving marker —
    // don't treat that as the user picking a new pin location.
    if (context.read<AppState>().isNavigating) return;

    String? address;
    try {
      final placemarks = await placemarkFromCoordinates(
        center.latitude,
        center.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        address = [
          p.street,
          p.locality,
        ].where((part) => part != null && part.isNotEmpty).join(', ');
        if (address.isEmpty) address = null;
      }
    } catch (_) {
      // Geocoding unavailable — fall back to coordinates.
    }

    if (mounted) {
      context.read<AppState>().updateLocation(center, address: address);
    }
  }

  // ---------------------------------------------------------- map layers

  List<Polyline> _buildPolylines(AppState appState) {
    final points = appState.routePolylinePoints;
    if (points == null || (!_routeMode && !appState.isNavigating)) {
      return const [];
    }
    return [
      Polyline(
        points: points,
        strokeWidth: 5,
        color: Theme.of(context).colorScheme.primary,
      ),
    ];
  }

  List<Marker> _buildMarkers(AppState appState) {
    final markers = <Marker>[];
    if (_routeMode || appState.isNavigating) {
      final origin = appState.routeOrigin;
      if (origin != null) {
        markers.add(_pinMarker(origin, Colors.green, "Route start"));
      }
      final destination = appState.routeDestination;
      if (destination != null) {
        markers.add(_pinMarker(destination, Colors.red, "Route destination"));
      }
    }
    if (appState.isNavigating) {
      final status = appState.mockStatus;
      markers.add(
        Marker(
          point: LatLng(status.latitude, status.longitude),
          width: 36,
          height: 36,
          child: Semantics(
            label: "Simulated position",
            child: Transform.rotate(
              angle: status.bearing * math.pi / 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 6),
                  ],
                ),
                child: const Icon(
                  Icons.navigation,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Marker _pinMarker(LatLng point, Color color, String label) {
    return Marker(
      point: point,
      width: 36,
      height: 36,
      alignment: Alignment.topCenter,
      child: Semantics(
        label: label,
        child: Icon(
          Icons.location_pin,
          size: 36,
          color: color,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 6)],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _handleCameraRequest(appState);
    _handleFollowRoute(appState);

    Widget tileLayer = TileLayer(
      urlTemplate: AppConstants.osmTileUrl,
      userAgentPackageName: AppConstants.tileUserAgentPackage,
    );
    if (isDark) {
      tileLayer = ColorFiltered(
        colorFilter: const ColorFilter.matrix(_darkTileMatrix),
        child: tileLayer,
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _buildSearchBar(context),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController.mapController,
            options: MapOptions(
              initialCenter: appState.mapStartLocation,
              initialZoom: appState.mapStartZoom,
              minZoom: 2,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: _onPositionChanged,
              onMapReady: () {
                _onCameraIdle(_mapController.mapController.camera.center);
              },
            ),
            children: [
              tileLayer,
              PolylineLayer(polylines: _buildPolylines(appState)),
              MarkerLayer(markers: _buildMarkers(appState)),
            ],
          ),
          if (!appState.isNavigating) _buildCenterPin(context),
          _buildTopOverlays(context, appState),
          _buildControlsOverlay(context, appState),
        ],
      ),
    );
  }

  Widget _buildCenterPin(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 46),
          child: Semantics(
            label: "Selected mock location pin",
            child: Icon(
              Icons.location_pin,
              size: 50,
              color: Theme.of(context).colorScheme.primary,
              shadows: const [Shadow(color: Colors.black38, blurRadius: 8)],
            ),
          ),
        ),
      ),
    );
  }

  /// Setup warning banner and live "mocking" badge, stacked under the
  /// search bar.
  Widget _buildTopOverlays(BuildContext context, AppState appState) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
      left: 20,
      right: 20,
      child: Column(
        children: [
          if (appState.isMockLocationApp == false) ...[
            _buildSetupBanner(context),
            const SizedBox(height: 8),
          ],
          if (appState.isMocking) _buildMockingBadge(context, appState),
        ],
      ),
    );
  }

  Widget _buildMockingBadge(BuildContext context, AppState appState) {
    final navigating = appState.isNavigating;
    return Semantics(
      liveRegion: true,
      label: navigating ? "Route simulation active" : "Location mocking active",
      child: Material(
        color: Colors.green.shade700,
        borderRadius: BorderRadius.circular(20),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                navigating ? Icons.route : Icons.gps_fixed,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                navigating ? "SIMULATING ROUTE" : "MOCKING",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showDialog(
          context: context,
          builder: (_) => const OnboardingDialog(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Not set as mock location app — tap to fix",
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onErrorContainer,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ search bar

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Row(
        children: [
          Expanded(
            child: TypeAheadField<PlaceSuggestion>(
              controller: _searchController,
              debounceDuration: const Duration(milliseconds: 350),
              builder: (context, controller, focusNode) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: "Search places…",
                    border: InputBorder.none,
                    icon: const Icon(Icons.search),
                    suffixIcon: controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: "Clear search",
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              controller.clear();
                              setState(() {});
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                );
              },
              suggestionsCallback: (pattern) async {
                _lastSearchQuery = pattern.trim();
                if (_lastSearchQuery.length < 3) {
                  return const <PlaceSuggestion>[];
                }
                return _searchService.search(
                  pattern,
                  near: context.read<AppState>().currentLocation,
                );
              },
              loadingBuilder: (context) => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              emptyBuilder: (context) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _lastSearchQuery.length < 3
                      ? "Type at least 3 characters to search"
                      : "No places found",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              errorBuilder: (context, error) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Search failed — check your connection",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              itemBuilder: (context, suggestion) {
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(
                    suggestion.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: suggestion.description.isEmpty
                      ? null
                      : Text(
                          suggestion.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                );
              },
              onSelected: (suggestion) {
                final appState = context.read<AppState>();
                final address = suggestion.description.isEmpty
                    ? suggestion.name
                    : "${suggestion.name}, ${suggestion.description}";
                _searchController.text = suggestion.name;
                FocusScope.of(context).unfocus();
                appState.updateLocation(suggestion.location, address: address);
                appState.requestCamera(suggestion.location, zoom: 16);
              },
            ),
          ),
          IconButton(
            tooltip: "Saved locations",
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => _openFavorites(context),
          ),
          PopupMenuButton<String>(
            tooltip: "More options",
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  context.read<AppState>().openSettings();
                case 'about':
                  _showAbout(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.developer_mode),
                  title: Text("Developer settings"),
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text("About GPS Mock"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: "GPS Mock",
      applicationVersion: "2.0.0",
      applicationIcon: const Icon(Icons.location_pin, size: 40),
      children: const [
        Text(
          "GPS Mock spoofs your device's location and simulates trips "
          "along real roads. It is the testing companion for My Globe, "
          "a maps & navigation project.\n\n"
          "Maps © OpenStreetMap contributors. Search by Photon, "
          "routing by OSRM — all free, keyless services.",
        ),
      ],
    );
  }

  // ------------------------------------------------------------- actions

  Future<void> _openFavorites(BuildContext context) async {
    final selected = await showModalBottomSheet<LocationItem>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const FavoritesSheet(),
    );
    if (selected != null && context.mounted) {
      final appState = context.read<AppState>();
      final latLng = LatLng(selected.latitude, selected.longitude);
      appState.updateLocation(latLng, address: selected.address);
      appState.requestCamera(latLng, zoom: 16);
    }
  }

  Future<void> _toggleMocking(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final appState = context.read<AppState>();
    final result = await appState.toggleMocking();
    if (!context.mounted) return;

    switch (result) {
      case MockToggleResult.needsSetup:
        showDialog(context: context, builder: (_) => const OnboardingDialog());
      case MockToggleResult.noLocation:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Move the map to pick a location first."),
          ),
        );
      case MockToggleResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appState.lastError ?? "Could not start mocking."),
          ),
        );
      case MockToggleResult.started:
        _announce(context, "Location mocking started");
      case MockToggleResult.stopped:
        _announce(context, "Location mocking stopped");
    }
  }

  /// Screen-reader announcement for state changes that have no focusable
  /// widget of their own.
  void _announce(BuildContext context, String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }

  void _copyCoordinates(BuildContext context, LatLng location) {
    final text =
        "${location.latitude.toStringAsFixed(6)}, "
        "${location.longitude.toStringAsFixed(6)}";
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Copied $text")),
    );
  }

  void _shareLocation(AppState appState) {
    final loc = appState.currentLocation;
    if (loc == null) return;
    SharePlus.instance.share(
      ShareParams(
        text:
            "${appState.currentAddress}\n"
            "${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}\n"
            "https://www.openstreetmap.org/?mlat=${loc.latitude}&mlon=${loc.longitude}#map=16/${loc.latitude}/${loc.longitude}",
        subject: "Location from GPS Mock",
      ),
    );
  }

  // ------------------------------------------------------- bottom overlay

  Widget _buildFollowButton(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: "follow_route",
      tooltip: _followRoute
          ? "Stop following mock position"
          : "Follow mock position",
      backgroundColor: _followRoute
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      onPressed: () => setState(() {
        _followRoute = !_followRoute;
        _lastFollowedPosition = null;
      }),
      child: const Icon(Icons.navigation),
    );
  }

  Widget _buildMyLocationButton(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: "my_location",
      tooltip: "Go to my real location",
      onPressed: () async {
        final moved = await context.read<AppState>().moveToRealLocation();
        if (!moved && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Couldn't get your location. Check that location is "
                "enabled and permission is granted.",
              ),
            ),
          );
        }
      },
      child: const Icon(Icons.my_location),
    );
  }

  Widget _buildControlsOverlay(BuildContext context, AppState appState) {
    final showRoutePanel = _routeMode || appState.isNavigating;
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // OpenStreetMap requires visible attribution on the map screen.
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 4),
            child: Text(
              AppConstants.osmAttribution,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: 0.75,
                ),
                backgroundColor: Theme.of(context).colorScheme.surface
                    .withValues(alpha: 0.6),
              ),
            ),
          ),
          // Anchored above the card so they never overlap it, whatever the
          // card's current height.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (appState.isNavigating) ...[
                _buildFollowButton(context),
                const SizedBox(width: 8),
              ],
              _buildMyLocationButton(context),
            ],
          ),
          const SizedBox(height: 8),
          _buildControlsCard(context, appState, showRoutePanel),
        ],
      ),
    );
  }

  Widget _buildControlsCard(
    BuildContext context,
    AppState appState,
    bool showRoutePanel,
  ) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text("Fixed"),
                  icon: Icon(Icons.location_on, size: 16),
                ),
                ButtonSegment(
                  value: true,
                  label: Text("Route"),
                  icon: Icon(Icons.route, size: 16),
                ),
              ],
              selected: {showRoutePanel},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: appState.isNavigating
                  ? null // locked to Route while a simulation runs
                  : (selection) {
                      setState(() => _routeMode = selection.first);
                      // Sensible default: start the trip from wherever
                      // the pin currently is.
                      final state = context.read<AppState>();
                      if (_routeMode &&
                          state.routeOrigin == null &&
                          state.currentLocation != null) {
                        state.setRouteOrigin(
                          state.currentLocation!,
                          state.currentAddress,
                        );
                      }
                    },
            ),
            const SizedBox(height: 12),
            if (showRoutePanel)
              const RoutePanel()
            else
              _buildFixedControls(context, appState),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedControls(BuildContext context, AppState appState) {
    final location = appState.currentLocation;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appState.currentAddress,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        if (location != null)
          Tooltip(
            message: "Copy coordinates",
            child: ActionChip(
              avatar: const Icon(Icons.copy, size: 14),
              label: Text(
                "${location.latitude.toStringAsFixed(5)}, "
                "${location.longitude.toStringAsFixed(5)}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: () => _copyCoordinates(context, location),
            ),
          )
        else
          Text("—", style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: "Save as favorite",
              iconSize: 22,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.favorite_border),
              onPressed: location == null
                  ? null
                  : () => showDialog(
                      context: context,
                      builder: (_) => const SaveFavoriteDialog(),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _toggleMocking(context),
                icon: Icon(appState.isMocking ? Icons.stop : Icons.play_arrow),
                label: Text(
                  appState.isMocking ? "STOP MOCKING" : "START MOCKING",
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: appState.isMocking
                      ? Colors.red.shade700
                      : Colors.green.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: "Share location",
              iconSize: 22,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.share),
              onPressed: location == null
                  ? null
                  : () => _shareLocation(appState),
            ),
          ],
        ),
      ],
    );
  }
}
