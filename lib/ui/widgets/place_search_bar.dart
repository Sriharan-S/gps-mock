import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/services/search_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

/// What a place picker hands back.
sealed class PlaceChoice {
  const PlaceChoice();
}

/// A concrete place the caller can use straight away.
class PlacePicked extends PlaceChoice {
  const PlacePicked(this.location, this.label);

  final LatLng location;
  final String label;
}

/// The user would rather point at the map than describe the place.
class PlacePickOnMap extends PlaceChoice {
  const PlacePickOnMap();
}

/// Kinds of row a place search can offer.
enum _EntryKind { coordinate, result, recent, favorite, chooseOnMap, here }

class _Entry {
  const _Entry({
    required this.kind,
    required this.icon,
    required this.title,
    this.subtitle,
    this.location,
  });

  final _EntryKind kind;
  final IconData icon;
  final String title;
  final String? subtitle;
  final LatLng? location;
}

/// Builds the suggestion rows for a query.
///
/// Shared by the map's expanding search bar and the full-screen picker so both
/// offer exactly the same things: coordinates typed or pasted straight in,
/// Photon results, recent searches, saved locations, the current pin, and —
/// where the caller supports it — picking a point off the map.
class _PlaceSearchEngine {
  _PlaceSearchEngine(this._service);

  final SearchService _service;

  Future<List<_Entry>> entries(
    String rawQuery,
    AppState appState, {
    required bool allowMapPick,
  }) async {
    final query = rawQuery.trim();
    final coordinates = SearchService.parseCoordinates(query);

    if (coordinates != null) {
      return [
        _Entry(
          kind: _EntryKind.coordinate,
          icon: Icons.my_location,
          title: 'Go to these coordinates',
          subtitle: '${coordinates.latitude.toStringAsFixed(6)}, '
              '${coordinates.longitude.toStringAsFixed(6)}',
          location: coordinates,
        ),
      ];
    }

    if (query.isEmpty) {
      return [
        if (allowMapPick)
          const _Entry(
            kind: _EntryKind.chooseOnMap,
            icon: Icons.touch_app_outlined,
            title: 'Choose on the map',
            subtitle: 'Tap the exact point you want',
          ),
        if (appState.currentLocation != null)
          _Entry(
            kind: _EntryKind.here,
            icon: Icons.center_focus_strong,
            title: 'Use the current pin',
            // The address is an instruction until the pin has been named;
            // show where it actually is instead.
            subtitle: appState.hasNamedLocation
                ? appState.currentAddress
                : '${appState.currentLocation!.latitude.toStringAsFixed(5)}, '
                    '${appState.currentLocation!.longitude.toStringAsFixed(5)}',
            location: appState.currentLocation,
          ),
        for (final term in appState.recentSearches)
          _Entry(
            kind: _EntryKind.recent,
            icon: Icons.history,
            title: term,
          ),
        for (final favorite in appState.favorites)
          _Entry(
            kind: _EntryKind.favorite,
            icon: Icons.bookmark,
            title: favorite.name,
            subtitle: favorite.address,
            location: LatLng(favorite.latitude, favorite.longitude),
          ),
      ];
    }

    if (query.length < 3) return const [];

    final results = await _service.search(
      query,
      near: appState.currentLocation,
    );
    return [
      for (final result in results)
        _Entry(
          kind: _EntryKind.result,
          icon: Icons.place_outlined,
          title: result.name,
          subtitle: result.description.isEmpty ? null : result.description,
          location: result.location,
        ),
    ];
  }
}

Widget _entryTile(
  BuildContext context,
  _Entry entry, {
  required VoidCallback onTap,
}) {
  final scheme = Theme.of(context).colorScheme;
  final highlighted = entry.kind == _EntryKind.coordinate ||
      entry.kind == _EntryKind.chooseOnMap ||
      entry.kind == _EntryKind.here;
  return ListTile(
    onTap: onTap,
    leading: CircleAvatar(
      radius: 20,
      backgroundColor:
          highlighted ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: Icon(
        entry.icon,
        size: 20,
        color: highlighted ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
    ),
    title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: entry.subtitle == null
        ? null
        : Text(entry.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

Widget _emptyMessage(BuildContext context, String title, String message) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
    child: Column(
      children: [
        Icon(Icons.travel_explore, size: 44, color: scheme.outline),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

/// Material 3 search for the map: a docked bar that expands in place into a
/// full-screen view of suggestions.
///
/// Suggestions are produced inside [SearchAnchor.suggestionsBuilder], which is
/// the only thing the anchor re-runs when the query changes — building them
/// from the parent's state would leave the view showing stale results.
class PlaceSearchBar extends StatefulWidget {
  const PlaceSearchBar({
    super.key,
    required this.onSelected,
    this.hintText = 'Search a place or coordinates',
  });

  final ValueChanged<PlacePicked> onSelected;
  final String hintText;

  @override
  State<PlaceSearchBar> createState() => _PlaceSearchBarState();
}

class _PlaceSearchBarState extends State<PlaceSearchBar> {
  final SearchController _controller = SearchController();
  final _PlaceSearchEngine _engine = _PlaceSearchEngine(SearchService());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SearchAnchor(
      searchController: _controller,
      isFullScreen: true,
      viewHintText: widget.hintText,
      viewLeading: IconButton(
        tooltip: 'Close search',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => _controller.closeView(null),
      ),
      viewTrailing: [
        IconButton(
          tooltip: 'Paste coordinates',
          icon: const Icon(Icons.content_paste_rounded),
          onPressed: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            final text = data?.text?.trim();
            if (text == null || text.isEmpty) return;
            _controller.text = text;
          },
        ),
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.close),
          onPressed: _controller.clear,
        ),
      ],
      builder: (context, controller) => Material(
        color: scheme.surfaceContainerHigh,
        elevation: 4,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: controller.openView,
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.search, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.hintText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      suggestionsBuilder: (context, controller) async {
        final query = controller.text;
        final appState = context.read<AppState>();

        // Debounce inside the builder: the anchor re-runs this on every
        // keystroke, and a stale run must not overwrite a newer one.
        if (query.trim().length >= 3) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          if (controller.text != query) return const <Widget>[];
        }

        final entries = await _engine.entries(
          query,
          appState,
          allowMapPick: false,
        );
        if (!context.mounted || controller.text != query) {
          return const <Widget>[];
        }

        if (entries.isEmpty) {
          return [
            _emptyMessage(
              context,
              query.trim().length < 3 ? 'Search anywhere' : 'No places found',
              query.trim().length < 3
                  ? 'Type a place name, or paste coordinates like '
                      '"12.9716, 77.5946".'
                  : 'Check the spelling, or paste coordinates instead.',
            ),
          ];
        }

        return [
          for (final entry in entries)
            _entryTile(
              context,
              entry,
              onTap: () {
                if (entry.kind == _EntryKind.recent) {
                  controller.text = entry.title;
                  return;
                }
                final location = entry.location;
                if (location == null) return;
                if (entry.kind == _EntryKind.result) {
                  appState.rememberSearch(entry.title);
                }
                HapticFeedback.selectionClick();
                controller
                  ..closeView(null)
                  ..clear();
                widget.onSelected(PlacePicked(location, entry.title));
              },
            ),
        ];
      },
    );
  }
}

/// The full-screen place picker used for route waypoints.
///
/// This is a search *screen*, not a bar that opens another one: the field in
/// the app bar is the search, and results fill the page beneath it.
class PlaceSearchPage extends StatefulWidget {
  const PlaceSearchPage({super.key, required this.title});

  final String title;

  static Future<PlaceChoice?> push(BuildContext context, String title) {
    return Navigator.of(context).push<PlaceChoice>(
      MaterialPageRoute(builder: (_) => PlaceSearchPage(title: title)),
    );
  }

  @override
  State<PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<PlaceSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final _PlaceSearchEngine _engine = _PlaceSearchEngine(SearchService());

  Timer? _debounce;
  String _query = '';
  List<_Entry> _entries = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _refresh('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    setState(() => _query = query);
    if (query.length >= 3 && SearchService.parseCoordinates(query) == null) {
      setState(() => _searching = true);
      _debounce = Timer(
        const Duration(milliseconds: 320),
        () => _refresh(query),
      );
    } else {
      _refresh(query);
    }
  }

  Future<void> _refresh(String query) async {
    final entries = await _engine.entries(
      query,
      context.read<AppState>(),
      allowMapPick: true,
    );
    if (!mounted || _query != query.trim()) return;
    setState(() {
      _entries = entries;
      _searching = false;
    });
  }

  void _choose(_Entry entry) {
    switch (entry.kind) {
      case _EntryKind.recent:
        _controller.text = entry.title;
        _onChanged(entry.title);
      case _EntryKind.chooseOnMap:
        Navigator.pop(context, const PlacePickOnMap());
      default:
        final location = entry.location;
        if (location == null) return;
        if (entry.kind == _EntryKind.result) {
          context.read<AppState>().rememberSearch(entry.title);
        }
        HapticFeedback.selectionClick();
        Navigator.pop(context, PlacePicked(location, entry.title));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch so the entries rebuild when saved locations or recents change.
    context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Place name or "lat, lng"',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Paste coordinates',
                      icon: const Icon(Icons.content_paste_rounded, size: 20),
                      onPressed: () async {
                        final data =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        final text = data?.text?.trim();
                        if (text == null || text.isEmpty) return;
                        _controller.text = text;
                        _onChanged(text);
                      },
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _entries.isEmpty
                  ? _emptyMessage(
                      context,
                      _query.length < 3 ? 'Search anywhere' : 'No places found',
                      _query.length < 3
                          ? 'Type a place name, paste coordinates, or pick the '
                              'point straight off the map.'
                          : 'Check the spelling, or paste coordinates instead.',
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _entries.length,
                      itemBuilder: (context, index) => _entryTile(
                        context,
                        _entries[index],
                        onTap: () => _choose(_entries[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
