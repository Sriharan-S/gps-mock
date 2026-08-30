import 'package:flutter/material.dart';
import 'package:gps_mock/models/map_style.dart';
import 'package:gps_mock/models/offline_area.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/services/offline_map_service.dart';
import 'package:gps_mock/services/search_service.dart';
import 'package:gps_mock/ui/widgets/empty_state.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

/// Manages map tiles stored on the device.
///
/// Areas are added one at a time — a searched city, state or country, a saved
/// location, or the corridor of a route already simulated — and listed as a
/// country → state → district → city tree that can be pruned at any level.
class OfflineMapsPage extends StatefulWidget {
  const OfflineMapsPage({super.key});

  @override
  State<OfflineMapsPage> createState() => _OfflineMapsPageState();
}

class _OfflineMapsPageState extends State<OfflineMapsPage> {
  final OfflineMapService _service = OfflineMapService();

  List<OfflineArea> _areas = const [];
  bool _loading = true;
  OfflineDownloadProgress? _progress;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final areas = await _service.listAreas();
    if (!mounted) return;
    setState(() {
      _areas = areas;
      _loading = false;
    });
  }

  /// The style tiles are downloaded for. Offline regions are tied to one
  /// style document, so the download follows whichever basemap is in use.
  String _styleUrl(AppState appState) {
    final style = MapStyle.resolve(
      appState.mapStyle,
      darkTheme: Theme.of(context).brightness == Brightness.dark,
    );
    return style.styleUrl ?? MapStyle.lightUrl;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tree = AreaNode.buildTree(_areas);
    final totalBytes = _areas.fold(0, (sum, area) => sum + area.sizeBytes);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline maps'),
        actions: [
          if (_areas.isNotEmpty)
            IconButton(
              tooltip: 'Delete all offline maps',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _confirmDeleteEverything,
            ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _progress != null ? null : () => _addArea(appState),
        icon: const Icon(Icons.add),
        label: const Text('Add area'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_progress != null) _buildProgress(context),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _areas.isEmpty
                      ? EmptyState(
                          icon: Icons.cloud_download_outlined,
                          title: 'No offline maps yet',
                          message:
                              'Download a city, district, state or country and '
                              'its map tiles stay on the device — useful when '
                              'testing with no connection.',
                          action: FilledButton.icon(
                            onPressed: () => _addArea(appState),
                            icon: const Icon(Icons.add),
                            label: const Text('Add an area'),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                              child: Text(
                                '${_areas.length} area'
                                '${_areas.length == 1 ? '' : 's'} · '
                                '${_formatBytes(totalBytes)} on this device',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                            for (final node in tree)
                              _AreaNodeTile(
                                node: node,
                                onDelete: _confirmDeleteNode,
                                onDeleteArea: _confirmDeleteArea,
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final progress = _progress!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Downloading ${progress.name}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.fraction == 0 ? null : progress.fraction,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${progress.completedTiles} of ${progress.requiredTiles} tiles · '
            '${_formatBytes(progress.bytes)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- adding

  Future<void> _addArea(AppState appState) async {
    final source = await showModalBottomSheet<_AddSource>(
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
                'What should be available offline?',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.travel_explore),
              title: const Text('Search a place'),
              subtitle: const Text('A city, district, state or country'),
              onTap: () => Navigator.pop(sheetContext, _AddSource.search),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: const Text('Around a saved location'),
              subtitle: Text(
                appState.favorites.isEmpty
                    ? 'No saved locations yet'
                    : '${appState.favorites.length} saved',
              ),
              enabled: appState.favorites.isNotEmpty,
              onTap: () => Navigator.pop(sheetContext, _AddSource.favorite),
            ),
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: const Text('A route you simulated'),
              subtitle: Text(
                appState.routeAreas.isEmpty
                    ? 'No routes run yet'
                    : '${appState.routeAreas.length} recent',
              ),
              enabled: appState.routeAreas.isNotEmpty,
              onTap: () => Navigator.pop(sheetContext, _AddSource.route),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    switch (source) {
      case _AddSource.search:
        await _addFromSearch(appState);
      case _AddSource.favorite:
        await _addFromFavorite(appState);
      case _AddSource.route:
        await _addFromRoute(appState);
    }
  }

  Future<void> _addFromSearch(AppState appState) async {
    final area = await Navigator.of(context).push<PlaceArea>(
      MaterialPageRoute(builder: (_) => const _AreaSearchPage()),
    );
    if (area == null || !mounted) return;
    await _confirmAndDownload(
      appState,
      name: area.name,
      level: area.level,
      southWest: area.southWest,
      northEast: area.northEast,
      country: area.country,
      state: area.state,
      district: area.district,
    );
  }

  Future<void> _addFromFavorite(AppState appState) async {
    final favorite = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < appState.favorites.length; i++)
              ListTile(
                leading: const Icon(Icons.bookmark),
                title: Text(appState.favorites[i].name),
                subtitle: Text(appState.favorites[i].address),
                onTap: () => Navigator.pop(sheetContext, i),
              ),
          ],
        ),
      ),
    );
    if (favorite == null || !mounted) return;
    final item = appState.favorites[favorite];
    // Roughly a 6 km box around the saved point.
    const delta = 0.055;
    await _confirmAndDownload(
      appState,
      name: item.name,
      level: AreaLevel.spot,
      southWest: LatLng(item.latitude - delta, item.longitude - delta),
      northEast: LatLng(item.latitude + delta, item.longitude + delta),
    );
  }

  Future<void> _addFromRoute(AppState appState) async {
    final index = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < appState.routeAreas.length; i++)
              ListTile(
                leading: const Icon(Icons.route),
                title: Text(
                  appState.routeAreas[i].label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(sheetContext, i),
              ),
          ],
        ),
      ),
    );
    if (index == null || !mounted) return;
    final route = appState.routeAreas[index];
    // Pad the corridor so the road has context either side of it.
    const pad = 0.02;
    await _confirmAndDownload(
      appState,
      name: route.label,
      level: AreaLevel.spot,
      southWest: LatLng(
        route.southWest.latitude - pad,
        route.southWest.longitude - pad,
      ),
      northEast: LatLng(
        route.northEast.latitude + pad,
        route.northEast.longitude + pad,
      ),
    );
  }

  /// Shows what the download will cost before starting it — the point where
  /// "don't download the entire map" is actually enforced.
  Future<void> _confirmAndDownload(
    AppState appState, {
    required String name,
    required AreaLevel level,
    required LatLng southWest,
    required LatLng northEast,
    String country = '',
    String state = '',
    String district = '',
  }) async {
    final (minZoom, maxZoom) = level.zoomRange;
    final tiles = OfflineMapService.estimateTiles(
      southWest,
      northEast,
      minZoom,
      maxZoom,
    );
    final tooBig = tiles > OfflineMapService.maxTiles;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(tooBig ? Icons.warning_amber_rounded : Icons.download),
        title: Text(tooBig ? 'That area is too big' : 'Download $name?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tooBig
                  ? '$name needs roughly $tiles map tiles, more than the '
                      '${OfflineMapService.maxTiles} this app will store at '
                      'once. Pick a smaller area — a state or a city rather '
                      'than a whole country.'
                  : 'About $tiles tiles, roughly '
                      '${_formatBytes(OfflineMapService.estimateBytes(tiles))}, '
                      'at zoom ${minZoom.round()}–${maxZoom.round()}.',
            ),
            if (!tooBig) ...[
              const SizedBox(height: 12),
              Text(
                'Zoom levels beyond that stay online-only, so streets stay '
                'sharp where it matters without storing the world.',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tooBig ? 'OK' : 'Cancel'),
          ),
          if (!tooBig)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Download'),
            ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final styleUrl = _styleUrl(appState);
    setState(() {
      _progress = OfflineDownloadProgress(
        name: name,
        fraction: 0,
        completedTiles: 0,
        requiredTiles: tiles,
        bytes: 0,
      );
    });

    try {
      await _service.download(
        name: name,
        level: level,
        southWest: southWest,
        northEast: northEast,
        styleUrl: styleUrl,
        country: country,
        state: state,
        district: district,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() => _progress = null);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name is available offline')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _progress = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not download $name: $error')),
      );
    }
  }

  // ------------------------------------------------------------ deleting

  Future<void> _confirmDeleteArea(OfflineArea area) async {
    final confirmed = await _confirm(
      'Delete ${area.name}?',
      'Its map tiles (${area.sizeLabel}) will be removed from this device.',
    );
    if (confirmed != true) return;
    await _service.deleteArea(area.id);
    await _reload();
  }

  Future<void> _confirmDeleteNode(AreaNode node) async {
    final areas = node.allAreas;
    final confirmed = await _confirm(
      'Delete ${node.label}?',
      areas.length == 1
          ? 'Its map tiles will be removed from this device.'
          : 'All ${areas.length} downloaded areas inside it '
              '(${_formatBytes(node.totalBytes)}) will be removed.',
    );
    if (confirmed != true) return;
    await _service.deleteAreas(areas.map((area) => area.id));
    await _reload();
  }

  Future<void> _confirmDeleteEverything() async {
    final confirmed = await _confirm(
      'Delete all offline maps?',
      'Every downloaded area is removed. Maps keep working over the network.',
    );
    if (confirmed != true) return;
    await _service.deleteEverything();
    await _reload();
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

enum _AddSource { search, favorite, route }

/// One level of the offline tree. Nodes with children expand; every row can
/// be deleted, which removes everything beneath it.
class _AreaNodeTile extends StatelessWidget {
  const _AreaNodeTile({
    required this.node,
    required this.onDelete,
    required this.onDeleteArea,
  });

  final AreaNode node;
  final ValueChanged<AreaNode> onDelete;
  final ValueChanged<OfflineArea> onDeleteArea;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final areas = node.allAreas;
    final subtitle = '${areas.length} area${areas.length == 1 ? '' : 's'} · '
        '${_formatBytes(node.totalBytes)}';

    // A node holding a single area and nothing else is just that area.
    if (node.children.isEmpty && node.areas.length == 1) {
      return _AreaTile(area: node.areas.first, onDelete: onDeleteArea);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(_icon(node.level), color: scheme.primary),
          title: Text(
            node.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(subtitle),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Delete ${node.label}',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(node),
              ),
              const Icon(Icons.expand_more),
            ],
          ),
          children: [
            for (final area in node.areas)
              _AreaTile(area: area, onDelete: onDeleteArea),
            for (final child in node.children)
              _AreaNodeTile(
                node: child,
                onDelete: onDelete,
                onDeleteArea: onDeleteArea,
              ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(AreaLevel level) => switch (level) {
        AreaLevel.country => Icons.public,
        AreaLevel.state => Icons.map_outlined,
        AreaLevel.district => Icons.account_balance_outlined,
        AreaLevel.city => Icons.location_city,
        AreaLevel.spot => Icons.place_outlined,
      };
}

class _AreaTile extends StatelessWidget {
  const _AreaTile({required this.area, required this.onDelete});

  final OfflineArea area;
  final ValueChanged<OfflineArea> onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(
          _AreaNodeTile._icon(area.level),
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
      ),
      title: Text(area.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${area.level.label} · ${area.sizeLabel}'),
      trailing: IconButton(
        tooltip: 'Delete ${area.name}',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => onDelete(area),
      ),
    );
  }
}

/// Searches for places that have an extent worth downloading.
class _AreaSearchPage extends StatefulWidget {
  const _AreaSearchPage();

  @override
  State<_AreaSearchPage> createState() => _AreaSearchPageState();
}

class _AreaSearchPageState extends State<_AreaSearchPage> {
  final SearchService _service = SearchService();
  final TextEditingController _controller = TextEditingController();
  List<PlaceArea> _results = const [];
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 3) return;
    setState(() => _searching = true);
    final results = await _service.searchAreas(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose an area')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'City, district, state or country',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => _search(_controller.text),
                  ),
                ),
              ),
            ),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _results.isEmpty
                  ? EmptyState(
                      icon: Icons.travel_explore,
                      title: _searched
                          ? 'Nothing with a mappable area'
                          : 'Search for an area',
                      message: _searched
                          ? 'Try a broader place — a city or district rather '
                              'than a street address.'
                          : 'Only places with a real extent can be downloaded, '
                              'so search a city, district, state or country.',
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final area = _results[index];
                        final tiles = OfflineMapService.estimateTiles(
                          area.southWest,
                          area.northEast,
                          area.level.zoomRange.$1,
                          area.level.zoomRange.$2,
                        );
                        return ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              _AreaNodeTile._icon(area.level),
                              size: 20,
                            ),
                          ),
                          title: Text(area.name),
                          subtitle: Text(
                            [
                              area.level.label,
                              if (area.description.isNotEmpty) area.description,
                              '≈ ${_formatBytes(
                                OfflineMapService.estimateBytes(tiles),
                              )}',
                            ].join(' · '),
                          ),
                          onTap: () => Navigator.pop(context, area),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}
