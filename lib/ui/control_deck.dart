import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/services/route_service.dart';
import 'package:gps_mock/ui/widgets/place_search_bar.dart';
import 'package:gps_mock/ui/onboarding_dialog.dart';
import 'package:gps_mock/ui/save_favorite_dialog.dart';
import 'package:gps_mock/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// The deck docked to the bottom of the map.
///
/// It has two states. **Peek** is a single bar: what will be mocked, and one
/// round button to start or stop it — the common case never needs the sheet
/// open. **Open** adds the full controls for the active mode. The map stays
/// the hero either way; the deck never grows past half the screen.
class ControlDeck extends StatefulWidget {
  const ControlDeck({super.key, this.onHeightChanged});

  /// Reports the deck's rendered height so the map can keep the pin and the
  /// camera clear of it.
  final ValueChanged<double>? onHeightChanged;

  @override
  State<ControlDeck> createState() => _ControlDeckState();
}

class _ControlDeckState extends State<ControlDeck> {
  final GlobalKey _deckKey = GlobalKey();
  bool _open = true;

  void _reportHeight() {
    final box = _deckKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      widget.onHeightChanged?.call(box.size.height);
    }
  }

  void _setOpen(bool value) {
    if (_open == value) return;
    HapticFeedback.selectionClick();
    setState(() => _open = value);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final navigating = appState.isNavigating;
    final routeMode = appState.routeMode || navigating;

    WidgetsBinding.instance.addPostFrameCallback((_) => _reportHeight());

    return Material(
      key: _deckKey,
      color: scheme.surface,
      elevation: 12,
      shadowColor: Colors.black45,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              // Route mode keeps a bigger window on the map: the itinerary is
              // only meaningful next to the line it describes.
              maxHeight:
                  MediaQuery.of(context).size.height * (routeMode ? .46 : .52),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Grabber(
                  open: _open,
                  onToggle: () => _setOpen(!_open),
                  onDrag: _setOpen,
                ),
                _PeekBar(
                  open: _open,
                  onExpand: () => _setOpen(true),
                ),
                if (_open)
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!navigating) ...[
                            _ModeSwitch(routeMode: routeMode),
                            const SizedBox(height: 18),
                          ],
                          if (navigating)
                            const _LiveRoutePanel()
                          else if (routeMode)
                            const _RoutePlannerPanel()
                          else
                            const _FixedSpotPanel(),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The handle. Tapping toggles the deck; dragging it does the same with
/// direction, so the deck behaves the way a sheet is expected to.
class _Grabber extends StatelessWidget {
  const _Grabber({
    required this.open,
    required this.onToggle,
    required this.onDrag,
  });

  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<bool> onDrag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: open ? 'Collapse the controls' : 'Expand the controls',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() > 60) onDrag(velocity < 0);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Always-visible summary + the single primary action. This is the whole
/// interface most of the time: read what is targeted, tap once to mock it.
class _PeekBar extends StatelessWidget {
  const _PeekBar({required this.open, required this.onExpand});

  final bool open;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.status;

    final navigating = appState.isNavigating;
    final routeMode = appState.routeMode || navigating;
    final mocking = appState.isMocking;

    final title = navigating
        ? (appState.mockStatus.label.isEmpty
            ? 'Simulating a route'
            : appState.mockStatus.label)
        : routeMode
            ? _routeTitle(appState)
            : appState.currentAddress;

    final subtitle = navigating
        ? '${_duration(appState.mockStatus.remainingSeconds)} left · '
            '${(appState.mockStatus.progress.clamp(0.0, 1.0) * 100).round()}%'
        : routeMode
            ? _routeSubtitle(appState)
            : _coordinates(appState);

    // In route mode the primary action lives in the planner, next to the
    // timing it depends on — a peek-level start would hide what it commits to.
    final canActFromPeek = !routeMode || navigating;

    return InkWell(
      onTap: open ? null : onExpand,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 14, 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: mocking
                    ? status.liveContainer
                    : scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                routeMode ? Icons.route : Icons.place,
                size: 21,
                color:
                    mocking ? status.onLiveContainer : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (canActFromPeek) ...[
              const SizedBox(width: 12),
              _PrimaryOrb(
                mocking: mocking,
                onPressed: () =>
                    navigating ? _stopRoute(context) : _toggleFixed(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _routeTitle(AppState appState) {
    final from = appState.routeOriginLabel;
    final to = appState.routeDestinationLabel;
    if (from.isEmpty && to.isEmpty) return 'Plan a route';
    return '${from.isEmpty ? 'Start' : from} → ${to.isEmpty ? 'Destination' : to}';
  }

  static String _routeSubtitle(AppState appState) {
    if (appState.fetchingRoute) return 'Finding a route…';
    if (appState.routeError != null) return appState.routeError!;
    final route = appState.plannedRoute;
    if (route == null) return 'Pick a start and a destination';
    return '${_distance(route.distanceMeters)} · '
        '${_duration(route.osrmDurationSeconds.round())} to drive';
  }

  static String _coordinates(AppState appState) {
    final location = appState.currentLocation;
    if (location == null) return 'Drag the pin to choose a spot';
    return '${location.latitude.toStringAsFixed(5)}, '
        '${location.longitude.toStringAsFixed(5)}';
  }
}

/// The start/stop control: a filled circle that swaps colour and glyph with
/// the mocking state, so its meaning is readable at a glance.
class _PrimaryOrb extends StatelessWidget {
  const _PrimaryOrb({required this.mocking, required this.onPressed});

  final bool mocking;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).status;
    return Semantics(
      button: true,
      label: mocking ? 'Stop mocking' : 'Start mocking',
      child: Tooltip(
        message: mocking ? 'Stop mocking' : 'Start mocking',
        child: Material(
          color: mocking ? status.stop : status.live,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                mocking ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 30,
                color: mocking ? status.onStop : status.onLive,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed vs Route, as two labelled tiles rather than a cramped segmented bar.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.routeMode});

  final bool routeMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeTile(
            icon: Icons.place_outlined,
            label: 'Fixed spot',
            selected: !routeMode,
            onTap: () => context.read<AppState>().setRouteMode(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ModeTile(
            icon: Icons.alt_route,
            label: 'Route',
            selected: routeMode,
            onTap: () => context.read<AppState>().setRouteMode(true),
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color:
            selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- fixed spot

/// Fixed mode: the coordinates being held, and the things worth doing with
/// them. Starting and stopping lives in the peek bar above.
class _FixedSpotPanel extends StatelessWidget {
  const _FixedSpotPanel();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final location = appState.currentLocation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LATITUDE, LONGITUDE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      location == null
                          ? '—'
                          : '${location.latitude.toStringAsFixed(6)}, '
                              '${location.longitude.toStringAsFixed(6)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy coordinates',
                icon: const Icon(Icons.copy_rounded, size: 20),
                onPressed: location == null
                    ? null
                    : () {
                        final text = '${location.latitude.toStringAsFixed(6)}, '
                            '${location.longitude.toStringAsFixed(6)}';
                        Clipboard.setData(ClipboardData(text: text));
                        HapticFeedback.selectionClick();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Copied $text')),
                        );
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _QuickAction(
              icon: Icons.bookmark_add_outlined,
              label: 'Save',
              onPressed: location == null
                  ? null
                  : () => showDialog(
                        context: context,
                        builder: (_) => const SaveFavoriteDialog(),
                      ),
            ),
            _QuickAction(
              icon: Icons.ios_share,
              label: 'Share',
              onPressed: location == null
                  ? null
                  : () => SharePlus.instance.share(
                        ShareParams(
                          text: '${appState.currentAddress}\n'
                              '${location.latitude.toStringAsFixed(6)}, '
                              '${location.longitude.toStringAsFixed(6)}\n'
                              'https://www.openstreetmap.org/'
                              '?mlat=${location.latitude}'
                              '&mlon=${location.longitude}'
                              '#map=16/${location.latitude}/'
                              '${location.longitude}',
                          subject: 'Location from GPS Mock',
                        ),
                      ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A compact icon-over-label action. Sized to sit three-up in a row without
/// the heavy boxes the old panel used.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: enabled
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: .38),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: enabled
                      ? scheme.onSurface
                      : scheme.onSurface.withValues(alpha: .38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- route planner

/// Route mode: an itinerary on a timeline spine, then how long the trip
/// should take, then one commit button.
class _RoutePlannerPanel extends StatefulWidget {
  const _RoutePlannerPanel();

  @override
  State<_RoutePlannerPanel> createState() => _RoutePlannerPanelState();
}

class _RoutePlannerPanelState extends State<_RoutePlannerPanel> {
  int? _minutes;
  int? _prefilledFor;
  DateTime? _arriveBy;

  /// Keeps the minutes in step with the arrival time as the clock advances.
  int? get _effectiveMinutes {
    final target = _arriveBy;
    if (target == null) return _minutes;
    final minutes = target.difference(DateTime.now()).inSeconds / 60;
    return minutes < 1 ? null : minutes.ceil();
  }

  void _setMinutes(int value) {
    setState(() {
      _minutes = value.clamp(1, 100000);
      _arriveBy = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final route = appState.plannedRoute;

    // Seed the pace with the real driving time, once per fetched route.
    if (route != null && identityHashCode(route) != _prefilledFor) {
      _prefilledFor = identityHashCode(route);
      _minutes = math.max(1, (route.osrmDurationSeconds / 60).ceil());
      _arriveBy = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Itinerary(appState: appState),
        if (appState.fetchingRoute) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(minHeight: 3),
        ] else if (appState.routeError != null) ...[
          const SizedBox(height: 14),
          _RouteError(
              message: appState.routeError!, onRetry: appState.retryRouteFetch),
        ] else if (route != null) ...[
          const SizedBox(height: 18),
          _PaceControl(
            route: route,
            minutes: _effectiveMinutes,
            arriveBy: _arriveBy,
            onMinutes: _setMinutes,
            onPickArrival: _pickArrival,
            onClearArrival: () => setState(() => _arriveBy = null),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: route == null || (_effectiveMinutes ?? 0) <= 0
                    ? null
                    : () => _start(context),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('START ROUTE'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).status.live,
                  foregroundColor: Theme.of(context).status.onLive,
                ),
              ),
            ),
            if (appState.routeOrigin != null ||
                appState.routeDestination != null) ...[
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Clear the route',
                style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _minutes = null;
                    _prefilledFor = null;
                    _arriveBy = null;
                  });
                  appState.clearRoute();
                },
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _pickArrival() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 30))),
    );
    if (time == null) return;
    setState(() {
      _arriveBy =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _start(BuildContext context) async {
    final minutes = _effectiveMinutes;
    if (minutes == null) return;
    HapticFeedback.mediumImpact();
    final appState = context.read<AppState>();
    final result = await appState.startNavigation(minutes);
    if (!context.mounted) return;
    switch (result) {
      case MockToggleResult.needsSetup:
        showDialog(context: context, builder: (_) => const OnboardingDialog());
      case MockToggleResult.noLocation:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plan a route first.')),
        );
      case MockToggleResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appState.lastError ?? 'Could not start the route simulation.',
            ),
          ),
        );
      case MockToggleResult.started:
      case MockToggleResult.stopped:
        break;
    }
  }
}

/// Start, stops and destination drawn on a single timeline spine.
class _Itinerary extends StatelessWidget {
  const _Itinerary({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).status;
    final stops = appState.routeStops;
    final pending = appState.pendingWaypointPick;
    bool armed(WaypointSlot slot, [int index = 0]) =>
        pending != null && pending.slot == slot && pending.index == index;

    // Three waypoints fit comfortably; past that the list scrolls in place
    // rather than growing the deck over the map.
    final scrolls = stops.length > 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: scrolls ? 208 : 400),
            child: SingleChildScrollView(
              physics: scrolls
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  _WaypointRow(
                    color: status.origin,
                    armed: armed(WaypointSlot.origin),
                    isEndpoint: true,
                    showSpineAbove: false,
                    showSpineBelow: true,
                    label: appState.routeOriginLabel,
                    placeholder: 'Choose a start point',
                    onTap: () => _pick(context, WaypointSlot.origin),
                  ),
                  for (var i = 0; i < stops.length; i++)
                    _WaypointRow(
                      color: status.waypoint,
                      armed: armed(WaypointSlot.stop, i),
                      isEndpoint: false,
                      showSpineAbove: true,
                      showSpineBelow: true,
                      label: stops[i].label,
                      placeholder: 'Stop ${i + 1}',
                      onTap: () => _pick(context, WaypointSlot.stop, index: i),
                      onRemove: () => appState.removeRouteStop(i),
                    ),
                  _WaypointRow(
                    color: status.destination,
                    armed: armed(WaypointSlot.destination),
                    isEndpoint: true,
                    showSpineAbove: true,
                    showSpineBelow: false,
                    label: appState.routeDestinationLabel,
                    placeholder: 'Choose a destination',
                    onTap: () => _pick(context, WaypointSlot.destination),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Column(
          children: [
            IconButton(
              tooltip: 'Swap start and destination',
              icon: const Icon(Icons.swap_vert),
              onPressed: appState.routeOrigin != null ||
                      appState.routeDestination != null
                  ? appState.swapRouteEndpoints
                  : null,
            ),
            IconButton(
              tooltip: 'Add a stop',
              icon: const Icon(Icons.add_location_alt_outlined),
              onPressed: appState.routeOrigin == null
                  ? null
                  : () => _pick(context, WaypointSlot.newStop),
            ),
          ],
        ),
      ],
    );
  }

  /// Tapping a waypoint arms it for a map tap; tapping the armed waypoint
  /// again opens the search instead. That way the common case — "somewhere
  /// about here" — needs one tap and no typing, while naming a place is still
  /// one tap further.
  Future<void> _pick(
    BuildContext context,
    WaypointSlot slot, {
    int index = 0,
  }) async {
    final appState = context.read<AppState>();
    final pending = appState.pendingWaypointPick;
    final alreadyArmed =
        pending != null && pending.slot == slot && pending.index == index;

    if (!alreadyArmed) {
      HapticFeedback.selectionClick();
      appState.armWaypointPick(slot, index: index);
      return;
    }

    appState.cancelWaypointPick();
    await _search(context, appState, slot, index: index);
  }

  Future<void> _search(
    BuildContext context,
    AppState appState,
    WaypointSlot slot, {
    int index = 0,
  }) async {
    final title = switch (slot) {
      WaypointSlot.origin => 'Choose a start point',
      WaypointSlot.destination => 'Choose a destination',
      WaypointSlot.stop => 'Change this stop',
      WaypointSlot.newStop => 'Add a stop',
    };
    final choice = await PlaceSearchPage.push(context, title);
    switch (choice) {
      case null:
        return;
      case PlacePickOnMap():
        // The search handed the job back to the map.
        appState.armWaypointPick(slot, index: index);
      case PlacePicked(location: final location, label: final label):
        switch (slot) {
          case WaypointSlot.origin:
            appState.setRouteOrigin(location, label);
          case WaypointSlot.destination:
            appState.setRouteDestination(location, label);
          case WaypointSlot.stop:
            appState.updateRouteStop(index, location, label);
          case WaypointSlot.newStop:
            appState.addRouteStop(location, label);
        }
    }
  }
}

class _WaypointRow extends StatelessWidget {
  const _WaypointRow({
    required this.color,
    required this.armed,
    required this.isEndpoint,
    required this.showSpineAbove,
    required this.showSpineBelow,
    required this.label,
    required this.placeholder,
    required this.onTap,
    this.onRemove,
  });

  final Color color;

  /// True while this waypoint is waiting for a map tap.
  final bool armed;
  final bool isEndpoint;
  final bool showSpineAbove;
  final bool showSpineBelow;
  final String label;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = label.isEmpty;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Expanded(child: _spine(scheme, showSpineAbove)),
                Container(
                  width: isEndpoint ? 13 : 10,
                  height: isEndpoint ? 13 : 10,
                  decoration: BoxDecoration(
                    color: empty ? scheme.surface : color,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2.5),
                  ),
                ),
                Expanded(child: _spine(scheme, showSpineBelow)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: armed ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: armed ? 8 : 13,
                    horizontal: armed ? 10 : 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              empty ? placeholder : label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight:
                                    empty ? FontWeight.w400 : FontWeight.w500,
                                color: armed
                                    ? scheme.onPrimaryContainer
                                    : empty
                                        ? scheme.onSurfaceVariant
                                        : scheme.onSurface,
                              ),
                            ),
                            if (armed)
                              Text(
                                'Tap the map — or tap again to search',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onPrimaryContainer
                                      .withValues(alpha: .8),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (onRemove != null)
                        IconButton(
                          tooltip: 'Remove this stop',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: onRemove,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _spine(ColorScheme scheme, bool visible) {
    return Center(
      child: SizedBox(
        width: 2,
        child: visible
            ? ColoredBox(color: scheme.outlineVariant)
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// How long the simulated trip should take: a stepper on the headline number,
/// multipliers of the real driving time, or an arrival time to work back from.
class _PaceControl extends StatelessWidget {
  const _PaceControl({
    required this.route,
    required this.minutes,
    required this.arriveBy,
    required this.onMinutes,
    required this.onPickArrival,
    required this.onClearArrival,
  });

  final RouteResult route;
  final int? minutes;
  final DateTime? arriveBy;
  final ValueChanged<int> onMinutes;
  final VoidCallback onPickArrival;
  final VoidCallback onClearArrival;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final realistic = math.max(1, (route.osrmDurationSeconds / 60).ceil());
    final value = minutes;
    final kmh = value == null || value <= 0
        ? null
        : ((route.distanceMeters / 1000) / (value / 60)).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${_distance(route.distanceMeters)} trip',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (kmh != null)
                Text(
                  kmh > 300 ? '$kmh km/h — unrealistic' : '≈ $kmh km/h',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: kmh > 300 ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StepButton(
                icon: Icons.remove,
                tooltip: 'Shorter trip',
                onPressed: value == null || value <= 1
                    ? null
                    : () => onMinutes(value - _step(value)),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      value == null ? '—' : '$value',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      'minutes',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _StepButton(
                icon: Icons.add,
                tooltip: 'Longer trip',
                onPressed: value == null
                    ? null
                    : () => onMinutes(value + _step(value)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final preset in <(String, int)>[
                ('Realistic', realistic),
                ('2× faster', math.max(1, realistic ~/ 2)),
                ('4× faster', math.max(1, realistic ~/ 4)),
                ('5 min', 5),
              ])
                ChoiceChip(
                  label: Text(preset.$1),
                  selected: arriveBy == null && value == preset.$2,
                  onSelected: (_) => onMinutes(preset.$2),
                ),
            ],
          ),
          const Divider(height: 24),
          if (arriveBy == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onPickArrival,
                icon: const Icon(Icons.schedule, size: 18),
                label: const Text('Arrive by a set time instead'),
              ),
            )
          else
            Row(
              children: [
                Icon(Icons.schedule, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Arriving ${_clock(arriveBy!)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                    onPressed: onPickArrival, child: const Text('Change')),
                IconButton(
                  tooltip: 'Use a duration instead',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClearArrival,
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Coarser steps on long trips so the stepper stays usable.
  static int _step(int minutes) =>
      minutes >= 120 ? 15 : (minutes >= 30 ? 5 : 1);
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }
}

class _RouteError extends StatelessWidget {
  const _RouteError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- live route

/// While the simulation runs: progress, the numbers that matter, and a way
/// out. Stopping is also available from the peek bar.
class _LiveRoutePanel extends StatelessWidget {
  const _LiveRoutePanel();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = appState.mockStatus;
    final progress = status.progress.clamp(0.0, 1.0);
    final eta = DateTime.now().add(Duration(seconds: status.remainingSeconds));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _LiveStat(
              value: _duration(status.remainingSeconds),
              label: 'remaining',
            ),
            _LiveStat(value: _clock(eta), label: 'arrival'),
            _LiveStat(
              value: '${(status.speedMps * 3.6).round()} km/h',
              label: 'speed',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'When the trip finishes, GPS Mock keeps holding the destination as '
          'a fixed spot until you stop it.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LiveStat extends StatelessWidget {
  const _LiveStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- shared

Future<void> _toggleFixed(BuildContext context) async {
  HapticFeedback.mediumImpact();
  final appState = context.read<AppState>();
  final result = await appState.toggleMocking();
  if (!context.mounted) return;
  switch (result) {
    case MockToggleResult.needsSetup:
      showDialog(context: context, builder: (_) => const OnboardingDialog());
    case MockToggleResult.noLocation:
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drag the pin to a spot first.')),
      );
    case MockToggleResult.failed:
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appState.lastError ?? 'Could not start mocking.'),
        ),
      );
    case MockToggleResult.started:
    case MockToggleResult.stopped:
      break;
  }
}

void _stopRoute(BuildContext context) {
  HapticFeedback.mediumImpact();
  context.read<AppState>().stopNavigation();
}

String _distance(double meters) {
  if (meters >= 10000) return '${(meters / 1000).round()} km';
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${meters.round()} m';
}

String _duration(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes >= 60) return '${minutes ~/ 60} h ${minutes % 60} min';
  if (minutes >= 1) return '$minutes min';
  return '$seconds s';
}

String _clock(DateTime time) {
  final now = DateTime.now();
  final sameDay =
      time.year == now.year && time.month == now.month && time.day == now.day;
  final clock = '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
  return sameDay ? clock : '${time.day}/${time.month} $clock';
}
