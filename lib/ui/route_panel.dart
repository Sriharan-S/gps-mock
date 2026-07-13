import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/location_picker_sheet.dart';
import 'package:gps_mock/ui/onboarding_dialog.dart';
import 'package:provider/provider.dart';

/// How the mock trip duration is specified.
enum _DurationMode { minutes, arriveBy }

/// The "Route" mode of the bottom control panel: plan a trip between two
/// points (with optional stops) and simulate driving it in a chosen
/// duration — or by a chosen arrival time — or, while running, show live
/// progress with a stop control.
class RoutePanel extends StatefulWidget {
  const RoutePanel({super.key});

  @override
  State<RoutePanel> createState() => _RoutePanelState();
}

class _RoutePanelState extends State<RoutePanel> {
  final TextEditingController _durationController = TextEditingController();
  int? _prefilledForRoute;
  _DurationMode _mode = _DurationMode.minutes;
  DateTime? _arriveBy;

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  /// The effective trip duration in minutes, from whichever input mode is
  /// active. Null when not yet valid.
  int? get _effectiveMinutes {
    if (_mode == _DurationMode.minutes) {
      return int.tryParse(_durationController.text.trim());
    }
    final target = _arriveBy;
    if (target == null) return null;
    final minutes = target.difference(DateTime.now()).inSeconds / 60;
    return minutes < 1 ? null : minutes.ceil();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (appState.isNavigating) return _buildProgress(context, appState);
    return _buildPlanner(context, appState);
  }

  // -------------------------------------------------------------- planning

  Widget _buildPlanner(BuildContext context, AppState appState) {
    final route = appState.plannedRoute;

    // Prefill the duration with OSRM's realistic estimate once per route.
    if (route != null && identityHashCode(route) != _prefilledForRoute) {
      _prefilledForRoute = identityHashCode(route);
      _durationController.text = math
          .max(1, (route.osrmDurationSeconds / 60).ceil())
          .toString();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildWaypoints(context, appState),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: appState.routeOrigin == null
                ? null
                : () => _addStop(context),
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text("Add stop"),
          ),
        ),
        if (appState.fetchingRoute)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          )
        else if (appState.routeError != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  appState.routeError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: appState.retryRouteFetch,
                child: const Text("Retry"),
              ),
            ],
          )
        else if (route != null) ...[
          Text(
            "${_formatDistance(route.distanceMeters)} · "
            "realistic ${_formatDuration(route.osrmDurationSeconds.round())}",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _buildDurationInput(context, route),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: route == null || (_effectiveMinutes ?? 0) <= 0
                    ? null
                    : () => _startNavigation(context),
                icon: const Icon(Icons.play_arrow),
                label: const Text("START ROUTE"),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
              ),
            ),
            if (appState.routeOrigin != null ||
                appState.routeDestination != null) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: "Clear route",
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.close),
                onPressed: () {
                  _prefilledForRoute = null;
                  _durationController.clear();
                  _arriveBy = null;
                  appState.clearRoute();
                },
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildWaypoints(BuildContext context, AppState appState) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _EndpointButton(
                icon: Icons.trip_origin,
                iconColor: Colors.green,
                text: appState.routeOriginLabel.isEmpty
                    ? "Choose start"
                    : appState.routeOriginLabel,
                isPlaceholder: appState.routeOriginLabel.isEmpty,
                onTap: () => _pickEndpoint(context, target: _Target.origin),
              ),
              for (int i = 0; i < appState.routeStops.length; i++) ...[
                const SizedBox(height: 8),
                _EndpointButton(
                  icon: Icons.more_vert,
                  iconColor: Colors.orange,
                  text: appState.routeStops[i].label.isEmpty
                      ? "Stop ${i + 1}"
                      : appState.routeStops[i].label,
                  isPlaceholder: false,
                  onTap: () => _pickEndpoint(context, target: _Target.stop, stopIndex: i),
                  onRemove: () => appState.removeRouteStop(i),
                ),
              ],
              const SizedBox(height: 8),
              _EndpointButton(
                icon: Icons.place,
                iconColor: Colors.red,
                text: appState.routeDestinationLabel.isEmpty
                    ? "Choose destination"
                    : appState.routeDestinationLabel,
                isPlaceholder: appState.routeDestinationLabel.isEmpty,
                onTap: () => _pickEndpoint(context, target: _Target.destination),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: "Swap start and destination",
          icon: const Icon(Icons.swap_vert),
          onPressed:
              appState.routeOrigin != null || appState.routeDestination != null
              ? appState.swapRouteEndpoints
              : null,
        ),
      ],
    );
  }

  Widget _buildDurationInput(BuildContext context, route) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<_DurationMode>(
          segments: const [
            ButtonSegment(
              value: _DurationMode.minutes,
              label: Text("Duration"),
              icon: Icon(Icons.timer_outlined, size: 16),
            ),
            ButtonSegment(
              value: _DurationMode.arriveBy,
              label: Text("Arrive by"),
              icon: Icon(Icons.schedule, size: 16),
            ),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 12),
        if (_mode == _DurationMode.minutes)
          Row(
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: "Duration",
                    suffixText: "min",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _speedHint(route.distanceMeters),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickArrivalTime,
                icon: const Icon(Icons.event, size: 18),
                label: Text(
                  _arriveBy == null ? "Pick time" : _formatArrival(_arriveBy!),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _arriveByHint(route.distanceMeters),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ------------------------------------------------------------- pickers

  Future<void> _pickEndpoint(
    BuildContext context, {
    required _Target target,
    int stopIndex = 0,
  }) async {
    final title = switch (target) {
      _Target.origin => "Choose start point",
      _Target.destination => "Choose destination",
      _Target.stop => "Choose stop",
    };
    final picked = await LocationPickerSheet.show(context, title);
    if (picked == null || !context.mounted) return;
    final appState = context.read<AppState>();
    switch (target) {
      case _Target.origin:
        appState.setRouteOrigin(picked.location, picked.label);
      case _Target.destination:
        appState.setRouteDestination(picked.location, picked.label);
      case _Target.stop:
        appState.updateRouteStop(stopIndex, picked.location, picked.label);
    }
  }

  Future<void> _addStop(BuildContext context) async {
    final picked = await LocationPickerSheet.show(context, "Add a stop");
    if (picked == null || !context.mounted) return;
    context.read<AppState>().addRouteStop(picked.location, picked.label);
  }

  Future<void> _pickArrivalTime() async {
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
      _arriveBy = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _startNavigation(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final appState = context.read<AppState>();
    final minutes = _effectiveMinutes;
    if (minutes == null) return;

    final result = await appState.startNavigation(minutes);
    if (!context.mounted) return;
    switch (result) {
      case MockToggleResult.needsSetup:
        showDialog(context: context, builder: (_) => const OnboardingDialog());
      case MockToggleResult.noLocation:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Plan a route first.")),
        );
      case MockToggleResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appState.lastError ?? "Could not start the route simulation.",
            ),
          ),
        );
      case MockToggleResult.started:
      case MockToggleResult.stopped:
        break;
    }
  }

  String _speedHint(double distanceMeters) {
    final minutes = _effectiveMinutes;
    if (minutes == null || minutes <= 0) return "Enter a duration";
    final kmh = (distanceMeters / 1000) / (minutes / 60);
    final rounded = kmh.round();
    if (kmh > 300) return "≈ $rounded km/h — unrealistically fast";
    return "≈ $rounded km/h average speed";
  }

  String _arriveByHint(double distanceMeters) {
    final minutes = _effectiveMinutes;
    if (_arriveBy == null) return "Reach the destination by this time";
    if (minutes == null || minutes <= 0) return "Pick a time in the future";
    return "$minutes min trip · ${_speedHint(distanceMeters)}";
  }

  // ------------------------------------------------------------ navigating

  Widget _buildProgress(BuildContext context, AppState appState) {
    final status = appState.mockStatus;
    final kmh = (status.speedMps * 3.6).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          status.label.isEmpty ? "Simulating route" : status.label,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: status.progress.clamp(0.0, 1.0),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          status.arrived
              ? "Arrived — holding final position"
              : "${_formatDuration(status.remainingSeconds)} remaining · "
                    "$kmh km/h",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              HapticFeedback.mediumImpact();
              appState.stopNavigation();
            },
            icon: const Icon(Icons.stop),
            label: Text(status.arrived ? "FINISH" : "STOP ROUTE"),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- helpers

  static String _formatArrival(DateTime time) {
    final now = DateTime.now();
    final isToday = time.year == now.year &&
        time.month == now.month &&
        time.day == now.day;
    final clock =
        "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
    return isToday ? clock : "${time.day}/${time.month} $clock";
  }

  static String _formatDistance(double meters) {
    if (meters >= 10000) return "${(meters / 1000).round()} km";
    if (meters >= 1000) return "${(meters / 1000).toStringAsFixed(1)} km";
    return "${meters.round()} m";
  }

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes >= 60) return "${minutes ~/ 60} h ${minutes % 60} min";
    if (minutes >= 1) return "$minutes min";
    return "$seconds s";
  }
}

enum _Target { origin, destination, stop }

class _EndpointButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final bool isPlaceholder;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _EndpointButton({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.isPlaceholder,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: onRemove == null ? 12 : 4,
            top: 14,
            bottom: 14,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlaceholder
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                  ),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: "Remove stop",
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
