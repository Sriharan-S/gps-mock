import 'package:flutter/material.dart';
import 'package:gps_mock/models/map_style.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:provider/provider.dart';

/// Bottom sheet for choosing the base-map style. Every style is a free,
/// keyless tile service.
class MapStyleSheet extends StatelessWidget {
  const MapStyleSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const MapStyleSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text("Map style", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          RadioGroup<MapStyleId>(
            groupValue: appState.mapStyle,
            onChanged: (value) {
              if (value != null) {
                context.read<AppState>().setMapStyle(value);
                Navigator.pop(context);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final style in MapStyle.all)
                  RadioListTile<MapStyleId>(
                    value: style.id,
                    title: Text(style.name),
                    subtitle: Text(
                      style.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "In dark theme, Standard automatically uses the dark basemap.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
