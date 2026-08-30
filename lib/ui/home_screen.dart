import 'package:flutter/material.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/models/mock_history_entry.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/library_page.dart';
import 'package:gps_mock/ui/map_view.dart';
import 'package:gps_mock/services/update_service.dart';
import 'package:gps_mock/ui/settings_page.dart';
import 'package:gps_mock/ui/theme.dart';
import 'package:gps_mock/ui/update_dialog.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

/// App shell: a persistent map, a library of saved places and past sessions,
/// and settings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<MapViewState> _mapKey = GlobalKey<MapViewState>();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Check for a newer release once the shell is on screen. The helper is
    // silent when the user has snoozed for the day or the check fails.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybePromptForUpdate(context, UpdateService());
    });
  }

  void _showMapAt(LatLng target, String address) {
    setState(() => _index = 0);
    // Let the Map tab mount before driving its controller.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapKey.currentState?.selectAndFly(target, address);
    });
  }

  void _onShowOnMap(LocationItem item) {
    _showMapAt(LatLng(item.latitude, item.longitude), item.name);
  }

  /// "Route from here": seed the planner's start point and land on the map in
  /// route mode.
  void _onRouteFrom(LocationItem item) {
    final appState = context.read<AppState>();
    appState.setRouteMode(true);
    appState.setRouteOrigin(LatLng(item.latitude, item.longitude), item.name);
    setState(() => _index = 0);
  }

  void _onHistorySelected(MockHistoryEntry entry) {
    if (entry.isRoute) {
      // A route summary carries no stored geometry — just return to the map.
      setState(() => _index = 0);
      return;
    }
    _showMapAt(
      LatLng(entry.latitude, entry.longitude),
      entry.label.isEmpty ? 'Mocked location' : entry.label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final status = Theme.of(context).status;

    return Scaffold(
      // Keep every tab alive so the map never rebuilds its controller.
      body: IndexedStack(
        index: _index,
        children: [
          MapView(key: _mapKey),
          LibraryPage(
            onShowOnMap: _onShowOnMap,
            onRouteFrom: _onRouteFrom,
            onHistorySelected: _onHistorySelected,
          ),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          if (value == 1) appState.loadHistory();
        },
        destinations: [
          NavigationDestination(
            // A dot on the Map tab keeps a running mock visible from any tab.
            icon: Badge(
              isLabelVisible: appState.isMocking,
              backgroundColor: status.live,
              child: const Icon(Icons.map_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: appState.isMocking,
              backgroundColor: status.live,
              child: const Icon(Icons.map),
            ),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Badge.count(
              isLabelVisible: appState.favorites.isNotEmpty,
              count: appState.favorites.length,
              child: const Icon(Icons.bookmarks_outlined),
            ),
            selectedIcon: Badge.count(
              isLabelVisible: appState.favorites.isNotEmpty,
              count: appState.favorites.length,
              child: const Icon(Icons.bookmarks),
            ),
            label: 'Library',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
