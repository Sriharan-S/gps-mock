import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/models/mock_history_entry.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/library_page.dart';
import 'package:gps_mock/ui/map_view.dart';
import 'package:gps_mock/services/link_intake.dart';
import 'package:gps_mock/services/location_link.dart';
import 'package:gps_mock/services/search_service.dart';
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

  final LinkIntake _linkIntake = LinkIntake();
  final LocationLinkResolver _linkResolver = LocationLinkResolver();
  final SearchService _searchService = SearchService();
  StreamSubscription<String>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Locations opened or shared from other apps, including the one the
      // app was launched with.
      _linkSubscription = _linkIntake.links.listen(_onIncomingLink);
      _linkIntake.start();
      // Check for a newer release once the shell is on screen. The helper is
      // silent when the user has snoozed for the day or the check fails.
      maybePromptForUpdate(context, UpdateService());
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _linkIntake.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------- shared links

  Future<void> _onIncomingLink(String raw) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 20),
          content: Row(
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 14),
              Expanded(child: Text('Reading the shared location…')),
            ],
          ),
        ),
      );

    var result = await _linkResolver.resolve(raw);
    if (result is LinkPlaceQuery) result = await _lookUpPlace(result);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();

    switch (result) {
      case LinkLocation():
        await _useLinkedLocation(result);
      case LinkInvalid(:final reason):
        await _showInvalidLink(raw, reason);
      case LinkPlaceQuery() || LinkShortUrl():
        await _showInvalidLink(
          raw,
          'GPS Mock couldn\'t read a location from it.',
        );
    }
  }

  /// Turns a place name from a link into coordinates via the place search.
  Future<LinkResult> _lookUpPlace(LinkPlaceQuery query) async {
    final appState = context.read<AppState>();
    final results = await _searchService.search(
      query.query,
      near: appState.currentLocation,
    );
    if (results.isEmpty) {
      return LinkInvalid(
        'The link names "${query.query}", but no such place was found. Check '
        'your internet connection, or share the place as coordinates.',
      );
    }
    final best = results.first;
    return LinkLocation(
      best.location,
      label: best.name.isEmpty ? query.query : best.name,
      asDestination: query.asDestination,
    );
  }

  Future<void> _useLinkedLocation(LinkLocation link) async {
    final appState = context.read<AppState>();
    final label = link.label ??
        '${link.location.latitude.toStringAsFixed(6)}, '
            '${link.location.longitude.toStringAsFixed(6)}';

    if (appState.isNavigating) {
      final stop = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.route),
          title: const Text('A route is running'),
          content: Text(
            'Stop the route simulation to use "$label" from the shared link?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep route'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Stop route'),
            ),
          ],
        ),
      );
      if (stop != true || !mounted) return;
      await appState.stopNavigation();
      if (!mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    if (link.asDestination) {
      appState.setRouteMode(true);
      appState.setRouteDestination(link.location, label);
      setState(() => _index = 0);
      messenger.showSnackBar(
        SnackBar(content: Text('Route destination set to "$label"')),
      );
      return;
    }
    appState.setRouteMode(false);
    _showMapAt(link.location, label);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          appState.isMocking
              ? 'Now mocking "$label"'
              : 'Opened "$label" — tap the start button to mock it',
        ),
      ),
    );
  }

  Future<void> _showInvalidLink(String raw, String reason) {
    final shown = raw.length > 300 ? '${raw.substring(0, 300)}…' : raw;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          icon: Icon(Icons.link_off, color: theme.colorScheme.error),
          title: const Text('Couldn\'t open this location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(reason),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  shown,
                  maxLines: 5,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: raw));
                Navigator.pop(dialogContext);
              },
              child: const Text('Copy link'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
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
