import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/favorites_sheet.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:gps_mock/ui/onboarding_dialog.dart';
import 'package:geocoding/geocoding.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Completer<GoogleMapController> _controller = Completer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AppState>().checkPermissions();
      if (context.mounted) {
        showDialog(context: context, builder: (_) => const OnboardingDialog());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

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
            initialCameraPosition: CameraPosition(
              target: appState.currentLocation,
              zoom: 14.4746,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            onCameraIdle: () async {
              final controller = await _controller.future;
              final region = await controller.getVisibleRegion();
              final centerLat =
                  (region.northeast.latitude + region.southwest.latitude) / 2;
              final centerLng =
                  (region.northeast.longitude + region.southwest.longitude) / 2;
              final center = LatLng(centerLat, centerLng);

              List<Placemark> placemarks = [];
              try {
                placemarks = await placemarkFromCoordinates(
                  center.latitude,
                  center.longitude,
                );
              } catch (e) {
                // Ignore geocoding errors
              }

              String address = "Unknown Location";
              if (placemarks.isNotEmpty) {
                final p = placemarks.first;
                address = "${p.street}, ${p.locality}";
              }

              if (context.mounted) {
                context.read<AppState>().updateLocation(
                  center,
                  address: address,
                );
              }
            },
            markers: {},
          ),
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 30),
              child: Icon(
                Icons.location_on,
                size: 50,
                color: Colors.deepPurple,
              ),
            ),
          ),
          _buildControlsOverlay(context, appState),
        ],
      ),
      floatingActionButton: null,
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Row(
        children: [
          Expanded(
            child: TypeAheadField<Location>(
              builder: (context, controller, focusNode) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    hintText: "Search Location...",
                    border: InputBorder.none,
                    icon: Icon(Icons.search),
                  ),
                );
              },
              suggestionsCallback: (pattern) async {
                if (pattern.length < 3) return [];
                try {
                  return await locationFromAddress(pattern);
                } catch (e) {
                  return [];
                }
              },
              itemBuilder: (context, suggestion) {
                return ListTile(
                  leading: const Icon(Icons.location_on),
                  title: Text(
                    "${suggestion.latitude.toStringAsFixed(4)}, ${suggestion.longitude.toStringAsFixed(4)}",
                  ),
                  subtitle: const Text(
                    "Tap to select",
                  ), // Geocoding results don't give name directly easily here
                );
              },
              onSelected: (suggestion) async {
                final latLng = LatLng(
                  suggestion.latitude,
                  suggestion.longitude,
                );
                final controller = await _controller.future;

                // Animate to location
                controller.animateCamera(CameraUpdate.newLatLng(latLng));

                // Get address for display (since search result is just coords)
                List<Placemark> placemarks = [];
                String address = "Unknown Location";
                try {
                  placemarks = await placemarkFromCoordinates(
                    latLng.latitude,
                    latLng.longitude,
                  );
                  if (placemarks.isNotEmpty) {
                    final p = placemarks.first;
                    address = "${p.street}, ${p.locality}";
                  }
                } catch (e) {}

                if (context.mounted) {
                  context.read<AppState>().updateLocation(
                    latLng,
                    address: address,
                  );
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => const FavoritesSheet(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay(BuildContext context, AppState appState) {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
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
                "${appState.currentLocation.latitude.toStringAsFixed(5)}, ${appState.currentLocation.longitude.toStringAsFixed(5)}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(Icons.favorite_border),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          final nameController = TextEditingController(
                            text: appState.currentAddress,
                          );
                          return Dialog(
                            backgroundColor: Colors.transparent,
                            insetPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E1E),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white10),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black45,
                                    blurRadius: 20,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "New Favorite",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => Navigator.pop(context),
                                        borderRadius: BorderRadius.circular(20),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4.0),
                                          child: Icon(
                                            Icons.close,
                                            color: Colors.grey,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  const Text(
                                    "Address",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on_outlined,
                                          color: Colors.grey,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            appState.currentAddress,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    "Coordinates",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.map_outlined,
                                          color: Colors.grey,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            "${appState.currentLocation.latitude.toStringAsFixed(6)}, ${appState.currentLocation.longitude.toStringAsFixed(6)}",
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    "Name",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: nameController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.black26,
                                      hintText: "Enter a name...",
                                      hintStyle: const TextStyle(
                                        color: Colors.white24,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          style: TextButton.styleFrom(
                                            backgroundColor: Colors.white10,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text("Cancel"),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () {
                                            appState.addFavorite(
                                              nameController.text,
                                            );
                                            Navigator.pop(context);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF6C63FF,
                                            ),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text("Save"),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  FilledButton.icon(
                    onPressed: () => appState.toggleMocking(),
                    icon: Icon(
                      appState.isMocking ? Icons.stop : Icons.play_arrow,
                    ),
                    label: Text(appState.isMocking ? "STOP" : "START"),
                    style: FilledButton.styleFrom(
                      backgroundColor: appState.isMocking
                          ? Colors.red
                          : Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                  ),
                  IconButton(icon: Icon(Icons.share), onPressed: () {}),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
