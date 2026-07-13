import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/location_picker_sheet.dart';
import 'package:gps_mock/ui/onboarding_dialog.dart';
import 'package:provider/provider.dart';

/// The "Route" mode of the bottom control card: plan a trip between two
/// points and simulate driving it in a chosen duration, or — while a route
/// simulation is running — show live progress with a stop control.
class RoutePanel extends StatefulWidget {
  const RoutePanel({super.key});

  @override
  State<RoutePanel> createState() => _RoutePanelState();
}

class _RoutePanelState extends State<RoutePanel> {
  final TextEditingController _durationController = TextEditingController();
  int? _prefilledForRoute;

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  int? get _durationMinutes => int.tryParse(_durationController.text.trim());

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
        Row(
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
                    onTap: () => _pickEndpoint(context, isOrigin: true),
                  ),
                  const SizedBox(height: 8),
                  _EndpointButton(
                    icon: Icons.place,
                    iconColor: Colors.red,
                    text: appState.routeDestinationLabel.isEmpty
                        ? "Choose destination"
                        : appState.routeDestinationLabel,
                    isPlaceholder: appState.routeDestinationLabel.isEmpty,
                    onTap: () => _pickEndpoint(context, isOrigin: false),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: "Swap start and destination",
              icon: const Icon(Icons.swap_vert),
              onPressed:
                  appState.routeOrigin != null ||
                      appState.routeDestination != null
                  ? appState.swapRouteEndpoints
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
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
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: route == null || (_durationMinutes ?? 0) <= 0
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
              IconButton(
                tooltip: "Clear route",
                icon: const Icon(Icons.close),
                onPressed: () {
                  _prefilledForRoute = null;
                  _durationController.clear();
                  appState.clearRoute();
                },
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _pickEndpoint(
    BuildContext context, {
    required bool isOrigin,
  }) async {
    final picked = await LocationPickerSheet.show(
      context,
      isOrigin ? "Choose start point" : "Choose destination",
    );
    if (picked == null || !context.mounted) return;
    final appState = context.read<AppState>();
    if (isOrigin) {
      appState.setRouteOrigin(picked.location, picked.label);
    } else {
      appState.setRouteDestination(picked.location, picked.label);
    }
  }

  Future<void> _startNavigation(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final appState = context.read<AppState>();
    final minutes = _durationMinutes;
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
    final minutes = _durationMinutes;
    if (minutes == null || minutes <= 0) return "Enter a duration";
    final kmh = (distanceMeters / 1000) / (minutes / 60);
    final rounded = kmh.round();
    if (kmh > 300) return "≈ $rounded km/h — unrealistically fast";
    return "≈ $rounded km/h average speed";
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
        FilledButton.icon(
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
            padding: const EdgeInsets.symmetric(horizontal: 32),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- helpers

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

class _EndpointButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final bool isPlaceholder;
  final VoidCallback onTap;

  const _EndpointButton({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.isPlaceholder,
    required this.onTap,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
            ],
          ),
        ),
      ),
    );
  }
}
