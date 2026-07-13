import 'package:flutter/material.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/models/mock_history_entry.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/history_tab.dart';
import 'package:gps_mock/ui/map_view.dart';
import 'package:gps_mock/ui/saved_tab.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

/// App shell: a persistent map with a bottom navigation bar for the Saved
/// and History tabs. Selecting a location from either tab drives the map and
/// switches back to it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<MapViewState> _mapKey = GlobalKey<MapViewState>();
  int _index = 0;

  void _showMapAt(LatLng target, String address) {
    setState(() => _index = 0);
    // Let the Map tab mount before driving its controller.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapKey.currentState?.selectAndFly(target, address);
    });
  }

  void _onSavedSelected(LocationItem item) {
    _showMapAt(LatLng(item.latitude, item.longitude), item.address);
  }

  void _onHistorySelected(MockHistoryEntry entry) {
    if (entry.isRoute) {
      // No stored coordinates for a route summary — just return to the map.
      setState(() => _index = 0);
      return;
    }
    _showMapAt(
      LatLng(entry.latitude, entry.longitude),
      entry.label.isEmpty ? "Mocked location" : entry.label,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep all three tabs alive so the map never rebuilds its controller.
    final pages = [
      MapView(key: _mapKey),
      SavedTab(onSelect: _onSavedSelected),
      HistoryTab(onSelect: _onHistorySelected),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          if (value == 2) context.read<AppState>().loadHistory();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: "Map",
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks),
            label: "Saved",
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: "History",
          ),
        ],
      ),
    );
  }
}
