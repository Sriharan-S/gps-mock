import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/services/search_service.dart';
import 'package:gps_mock/ui/favorites_sheet.dart';
import 'package:gps_mock/ui/onboarding_dialog.dart';
import 'package:gps_mock/ui/save_favorite_dialog.dart';
import 'package:gps_mock/utils/map_styles.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final Completer<GoogleMapController> _controller = Completer();
  final SearchService _searchService = SearchService();
  final TextEditingController _searchController = TextEditingController();
  int _handledCameraToken = 0;
  String _lastSearchQuery = '';

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
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // The user may have just enabled us in Developer Settings.
      context.read<AppState>().refreshMockLocationCheck();
    }
  }

  Future<void> _animateTo(LatLng target, double zoom) async {
    final controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
  }

  /// Executes pending one-shot camera requests coming from the app state
  /// (startup calibration, search selection, favorites, my-location).
  void _handleCameraRequest(AppState appState) {
    final request = appState.cameraRequest;
    if (request != null && request.token != _handledCameraToken) {
      _handledCameraToken = request.token;
      _animateTo(request.target, request.zoom);
    }
  }

  Future<void> _onCameraIdle() async {
    final controller = await _controller.future;
    final region = await controller.getVisibleRegion();
    final center = LatLng(
      (region.northeast.latitude + region.southwest.latitude) / 2,
      (region.northeast.longitude + region.southwest.longitude) / 2,
    );

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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _handleCameraRequest(appState);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _buildSearchBar(context),
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            style: isDark ? MapStyles.dark : null,
            initialCameraPosition: CameraPosition(
              target: appState.mapStartLocation,
              zoom: appState.mapStartZoom,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              if (!_controller.isCompleted) _controller.complete(controller);
            },
            onCameraIdle: _onCameraIdle,
            markers: const {},
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Semantics(
                label: "Selected mock location pin",
                child: Icon(
                  Icons.location_on,
                  size: 50,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          if (appState.isMockLocationApp == false) _buildSetupBanner(context),
          _buildMyLocationButton(context),
          _buildControlsOverlay(context, appState),
        ],
      ),
    );
  }

  Widget _buildSetupBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
      left: 20,
      right: 20,
      child: Material(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showDialog(
            context: context,
            builder: (_) => const OnboardingDialog(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      ),
    );
  }

  Widget _buildMyLocationButton(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: 220,
      child: FloatingActionButton.small(
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
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  decoration: const InputDecoration(
                    hintText: "Search places…",
                    border: InputBorder.none,
                    icon: Icon(Icons.search),
                  ),
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
            icon: const Icon(Icons.list),
            onPressed: () => _openFavorites(context),
          ),
        ],
      ),
    );
  }

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
      case MockToggleResult.stopped:
        break; // The button state itself shows the change.
    }
  }

  void _shareLocation(AppState appState) {
    final loc = appState.currentLocation;
    if (loc == null) return;
    SharePlus.instance.share(
      ShareParams(
        text:
            "${appState.currentAddress}\n"
            "https://maps.google.com/?q=${loc.latitude},${loc.longitude}",
        subject: "Location from GPS Mock",
      ),
    );
  }

  Widget _buildControlsOverlay(BuildContext context, AppState appState) {
    final location = appState.currentLocation;
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                appState.currentAddress,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                location == null
                    ? "—"
                    : "${location.latitude.toStringAsFixed(5)}, "
                          "${location.longitude.toStringAsFixed(5)}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: "Save as favorite",
                    icon: const Icon(Icons.favorite_border),
                    onPressed: location == null
                        ? null
                        : () => showDialog(
                            context: context,
                            builder: (_) => const SaveFavoriteDialog(),
                          ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _toggleMocking(context),
                    icon: Icon(
                      appState.isMocking ? Icons.stop : Icons.play_arrow,
                    ),
                    label: Text(appState.isMocking ? "STOP" : "START"),
                    style: FilledButton.styleFrom(
                      backgroundColor: appState.isMocking
                          ? Colors.red
                          : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: "Share location",
                    icon: const Icon(Icons.share),
                    onPressed: location == null
                        ? null
                        : () => _shareLocation(appState),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
