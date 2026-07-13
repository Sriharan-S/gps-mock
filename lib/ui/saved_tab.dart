import 'package:flutter/material.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/widgets/favorite_card.dart';
import 'package:provider/provider.dart';

/// The "Saved" bottom-navigation tab: all saved locations. Tapping "Set"
/// selects the location and jumps back to the map.
class SavedTab extends StatelessWidget {
  final void Function(LocationItem item) onSelect;

  const SavedTab({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<AppState>().favorites;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              "Saved locations",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (favorites.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite_border,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    const Text("No favorites yet"),
                    const SizedBox(height: 4),
                    Text(
                      "On the map, tap the heart button to save the "
                      "current location",
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: favorites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final item = favorites[index];
                  return FavoriteCard(
                    item: item,
                    index: index,
                    onSet: () => onSelect(item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
