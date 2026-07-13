import 'package:flutter/material.dart';
import 'package:gps_mock/models/mock_history_entry.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:provider/provider.dart';

/// The "History" bottom-navigation tab: every mock session the native
/// service recorded — fixed locations and simulated routes, including ones
/// started from quick-settings tiles or widgets.
class HistoryTab extends StatelessWidget {
  final void Function(MockHistoryEntry entry) onSelect;

  const HistoryTab({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final history = appState.history;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Mock history",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: "Refresh",
                  icon: const Icon(Icons.refresh),
                  onPressed: appState.loadHistory,
                ),
                IconButton(
                  tooltip: "Clear history",
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: history.isEmpty
                      ? null
                      : () => _confirmClear(context, appState),
                ),
              ],
            ),
          ),
          if (history.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    const Text("Nothing mocked yet"),
                    const SizedBox(height: 4),
                    Text(
                      "Fixed locations and simulated routes will appear here",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: history.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = history[index];
                  return _HistoryTile(entry: entry, onTap: () => onSelect(entry));
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, AppState appState) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear history?"),
        content: const Text("All recorded mock sessions will be removed."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Clear"),
          ),
        ],
      ),
    );
    if (confirmed == true) await appState.clearHistory();
  }
}

class _HistoryTile extends StatelessWidget {
  final MockHistoryEntry entry;
  final VoidCallback onTap;

  const _HistoryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = entry.isRoute
        ? "${entry.fromLabel.isEmpty ? 'Route' : entry.fromLabel} → "
              "${entry.toLabel.isEmpty ? '?' : entry.toLabel}"
        : (entry.label.isEmpty
              ? "${entry.latitude.toStringAsFixed(4)}, ${entry.longitude.toStringAsFixed(4)}"
              : entry.label);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: entry.isRunning
            ? Colors.green.shade700
            : colorScheme.surfaceContainerHighest,
        child: Icon(
          entry.isRoute ? Icons.route : Icons.location_on,
          size: 20,
          color: entry.isRunning ? Colors.white : colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _subtitle(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: entry.isRunning
          ? const Text(
              "LIVE",
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            )
          : Icon(Icons.chevron_right, color: colorScheme.outline),
    );
  }

  String _subtitle() {
    final parts = <String>["Started ${_formatTime(entry.startedAt)}"];
    if (entry.isRoute) {
      if (entry.distanceMeters > 0) {
        parts.add(_formatDistance(entry.distanceMeters));
      }
      if (entry.plannedDurationSeconds > 0) {
        parts.add("planned ${_formatDuration(entry.plannedDurationSeconds)}");
      }
      if (entry.arrivedAt != null) {
        parts.add("arrived ${_formatTime(entry.arrivedAt!)}");
      } else if (entry.arrived) {
        parts.add("arrived");
      }
    }
    if (entry.endedAt != null) {
      parts.add(
        "ended ${_formatTime(entry.endedAt!)} "
        "(${_formatDuration(entry.duration.inSeconds)} total)",
      );
    }
    return parts.join(" · ");
  }

  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday = time.year == now.year &&
        time.month == now.month &&
        time.day == now.day;
    final clock =
        "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
    if (isToday) return clock;
    return "${time.day}/${time.month} $clock";
  }

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes >= 60) return "${minutes ~/ 60} h ${minutes % 60} min";
    if (minutes >= 1) return "$minutes min";
    return "$seconds s";
  }

  static String _formatDistance(double meters) {
    if (meters >= 10000) return "${(meters / 1000).round()} km";
    if (meters >= 1000) return "${(meters / 1000).toStringAsFixed(1)} km";
    return "${meters.round()} m";
  }
}
