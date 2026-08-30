import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/models/mock_history_entry.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/theme.dart';
import 'package:gps_mock/ui/widgets/empty_state.dart';
import 'package:provider/provider.dart';

enum _SavedSort { recent, name }

enum _HistoryFilter { all, spots, routes }

/// Saved locations and mock history in one place: what you keep on top, what
/// you did underneath.
///
/// Rows are plain, high-contrast list items rather than image cards — they
/// render instantly, work with no connection, and every action is reachable
/// from an explicit menu rather than a swipe only a sighted mouse-free user
/// would discover.
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.onShowOnMap,
    required this.onRouteFrom,
    required this.onHistorySelected,
  });

  final void Function(LocationItem item) onShowOnMap;
  final void Function(LocationItem item) onRouteFrom;
  final void Function(MockHistoryEntry entry) onHistorySelected;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  _SavedSort _sort = _SavedSort.recent;
  _HistoryFilter _historyFilter = _HistoryFilter.all;
  bool _historyExpanded = true;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final saved = _visibleSaved(appState);
    final history = appState.history.where((entry) {
      return switch (_historyFilter) {
        _HistoryFilter.all => true,
        _HistoryFilter.spots => !entry.isRoute,
        _HistoryFilter.routes => entry.isRoute,
      };
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: appState.loadHistory,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar.large(
                pinned: true,
                title: const Text('Library'),
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),

              // ------------------------------------------------ saved
              _SectionHeader(
                title: 'Saved locations',
                count: appState.favorites.length,
                trailing: appState.favorites.length < 2
                    ? null
                    : _sortMenu(),
              ),
              if (appState.favorites.length > 4)
                SliverToBoxAdapter(child: _filterField(context)),
              if (appState.favorites.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.bookmark_border,
                    title: 'Nothing saved yet',
                    message:
                        'Pick a spot on the map and tap Save. Saved places '
                        'also drive the quick-settings tiles and home-screen '
                        'widgets.',
                  ),
                )
              else if (saved.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.search_off,
                    title: 'Nothing matches "$_filter"',
                    message: 'Try a different name, or clear the filter.',
                  ),
                )
              else
                SliverList.builder(
                  itemCount: saved.length,
                  itemBuilder: (context, index) => _SavedRow(
                    item: saved[index],
                    position: index + 1,
                    total: saved.length,
                    originalIndex: appState.favorites.indexOf(saved[index]),
                    onShowOnMap: widget.onShowOnMap,
                    onRouteFrom: widget.onRouteFrom,
                  ),
                ),

              // ---------------------------------------------- history
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Divider(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              _SectionHeader(
                title: 'Mock history',
                count: appState.history.length,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (appState.history.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear history',
                        icon: const Icon(Icons.delete_sweep_outlined),
                        onPressed: () => _confirmClear(context, appState),
                      ),
                    IconButton(
                      tooltip: _historyExpanded
                          ? 'Hide history'
                          : 'Show history',
                      icon: Icon(
                        _historyExpanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: () => setState(
                        () => _historyExpanded = !_historyExpanded,
                      ),
                    ),
                  ],
                ),
              ),
              if (_historyExpanded) ...[
                if (appState.history.isNotEmpty)
                  SliverToBoxAdapter(child: _historyChips()),
                if (history.isEmpty)
                  SliverToBoxAdapter(
                    child: EmptyState(
                      icon: Icons.history,
                      title: appState.history.isEmpty
                          ? 'Nothing mocked yet'
                          : 'No sessions of this kind',
                      message: appState.history.isEmpty
                          ? 'Fixed spots and simulated routes show up here as '
                              'soon as you start mocking.'
                          : 'Try a different filter.',
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final entry = history[index];
                      final previous = index == 0 ? null : history[index - 1];
                      final showDay = previous == null ||
                          !_sameDay(previous.startedAt, entry.startedAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDay)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                24,
                                index == 0 ? 4 : 18,
                                24,
                                6,
                              ),
                              child: Text(
                                _dayLabel(entry.startedAt),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          _HistoryRow(
                            entry: entry,
                            onTap: () => widget.onHistorySelected(entry),
                          ),
                        ],
                      );
                    },
                  ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  List<LocationItem> _visibleSaved(AppState appState) {
    final query = _filter.trim().toLowerCase();
    final items = query.isEmpty
        ? [...appState.favorites]
        : appState.favorites
            .where((item) =>
                item.name.toLowerCase().contains(query) ||
                item.address.toLowerCase().contains(query))
            .toList();
    if (_sort == _SavedSort.name) {
      items.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    } else {
      // Favorites are appended as they are saved, so newest is last.
      final order = appState.favorites;
      items.sort((a, b) => order.indexOf(b).compareTo(order.indexOf(a)));
    }
    return items;
  }

  Widget _sortMenu() {
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        tooltip: 'Sort saved locations',
        icon: const Icon(Icons.sort),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        for (final sort in _SavedSort.values)
          MenuItemButton(
            leadingIcon: Icon(
              _sort == sort
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            onPressed: () => setState(() => _sort = sort),
            child: Text(
              sort == _SavedSort.recent ? 'Newest first' : 'By name',
            ),
          ),
      ],
    );
  }

  Widget _filterField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: TextField(
        controller: _filterController,
        onChanged: (value) => setState(() => _filter = value),
        decoration: InputDecoration(
          hintText: 'Filter saved locations',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _filter.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear filter',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _filterController.clear();
                    setState(() => _filter = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _historyChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          for (final filter in _HistoryFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: _historyFilter == filter,
                label: Text(switch (filter) {
                  _HistoryFilter.all => 'All',
                  _HistoryFilter.spots => 'Spots',
                  _HistoryFilter.routes => 'Routes',
                }),
                onSelected: (_) => setState(() => _historyFilter = filter),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, AppState appState) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_outlined),
        title: const Text('Clear history?'),
        content: const Text(
          'Every recorded mock session is removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await appState.clearHistory();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(DateTime time) {
    final now = DateTime.now();
    if (_sameDay(time, now)) return 'Today';
    if (_sameDay(time, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[time.month - 1];
    return time.year == now.year
        ? '${time.day} $month'
        : '${time.day} $month ${time.year}';
  }
}

/// A section title with its item count, rendered as a sliver so it can sit
/// between lists.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    this.trailing,
  });

  final String title;
  final int count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  count == 0 ? title : '$title ($count)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// One saved location. Tapping shows it on the map; every other action lives
/// in the menu, so nothing depends on discovering a swipe.
class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.item,
    required this.position,
    required this.total,
    required this.originalIndex,
    required this.onShowOnMap,
    required this.onRouteFrom,
  });

  final LocationItem item;
  final int position;
  final int total;
  final int originalIndex;
  final void Function(LocationItem item) onShowOnMap;
  final void Function(LocationItem item) onRouteFrom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        _delete(context);
        return true;
      },
      child: Semantics(
        // Spoken as one coherent row rather than four disconnected strings.
        label: 'Saved location $position of $total. ${item.name}. '
            '${item.address}',
        button: true,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onShowOnMap(item),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          _initials(item.name),
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${item.latitude.toStringAsFixed(4)}, '
                              '${item.longitude.toStringAsFixed(4)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.outline,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      _menu(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        tooltip: 'Actions for ${item.name}',
        icon: const Icon(Icons.more_vert),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.play_arrow_rounded),
          onPressed: () => _mockNow(context),
          child: const Text('Mock this now'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.map_outlined),
          onPressed: () => onShowOnMap(item),
          child: const Text('Show on map'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.alt_route),
          onPressed: () => onRouteFrom(item),
          child: const Text('Route from here'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.drive_file_rename_outline),
          onPressed: () => _rename(context),
          child: const Text('Rename'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.copy_rounded),
          onPressed: () {
            final text = '${item.latitude.toStringAsFixed(6)}, '
                '${item.longitude.toStringAsFixed(6)}';
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied $text')),
            );
          },
          child: const Text('Copy coordinates'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: () => _delete(context),
          child: const Text('Delete'),
        ),
      ],
    );
  }

  Future<void> _mockNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    HapticFeedback.mediumImpact();
    final result = await appState.mockFavoriteNow(item);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          switch (result) {
            MockToggleResult.started => 'Mocking "${item.name}"',
            MockToggleResult.needsSetup =>
              'Select GPS Mock as the mock location app first.',
            _ => appState.lastError ?? 'Could not start mocking.',
          },
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: item.name);
    final appState = context.read<AppState>();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename location'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) await appState.renameFavorite(item, name);
  }

  void _delete(BuildContext context) {
    final appState = context.read<AppState>();
    final removed = item;
    final index = originalIndex;
    appState.removeFavorite(item);
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${removed.name}"'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () => appState.insertFavorite(index, removed),
          ),
        ),
      );
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words[0].characters.first + words[1].characters.first)
        .toUpperCase();
  }
}

/// One recorded mock session.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.onTap});

  final MockHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.status;

    final title = entry.isRoute
        ? '${entry.fromLabel.isEmpty ? 'Route' : entry.fromLabel} → '
            '${entry.toLabel.isEmpty ? 'destination' : entry.toLabel}'
        : (entry.label.isEmpty
            ? '${entry.latitude.toStringAsFixed(4)}, '
                '${entry.longitude.toStringAsFixed(4)}'
            : entry.label);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: entry.isRunning
                      ? status.liveContainer
                      : scheme.surfaceContainerHighest,
                  child: Icon(
                    entry.isRoute ? Icons.route : Icons.location_on_outlined,
                    size: 20,
                    color: entry.isRunning
                        ? status.onLiveContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (entry.isRunning)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: status.live,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'LIVE',
                                style: TextStyle(
                                  color: status.onLive,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .6,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final fact in _facts()) _Pill(fact)],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> _facts() {
    final facts = <String>[_time(entry.startedAt)];
    if (entry.isRoute) {
      if (entry.distanceMeters > 0) facts.add(_distance(entry.distanceMeters));
      if (entry.plannedDurationSeconds > 0) {
        facts.add('planned ${_duration(entry.plannedDurationSeconds)}');
      }
      if (entry.arrivedAt != null) {
        facts.add('arrived ${_time(entry.arrivedAt!)}');
      } else if (entry.arrived) {
        facts.add('arrived');
      }
    }
    if (entry.endedAt != null) {
      facts.add('ran ${_duration(entry.duration.inSeconds)}');
    }
    return facts;
  }

  static String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  static String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes >= 60) return '${minutes ~/ 60} h ${minutes % 60} min';
    if (minutes >= 1) return '$minutes min';
    return '$seconds s';
  }

  static String _distance(double meters) {
    if (meters >= 10000) return '${(meters / 1000).round()} km';
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
