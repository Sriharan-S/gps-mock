import 'package:flutter/material.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/widgets/favorite_card.dart';
import 'package:provider/provider.dart';

/// Bottom sheet listing saved locations. Pops with the chosen [LocationItem]
/// when the user taps "Set" so the caller can move the map there.
class FavoritesSheet extends StatelessWidget {
  const FavoritesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final favorites = appState.favorites;

    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Saved Locations",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (favorites.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 40,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  const Text("No favorites yet"),
                  const SizedBox(height: 4),
                  Text(
                    "Save a location with the heart button",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: favorites.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final item = favorites[index];
                  return FavoriteCard(
                    item: item,
                    index: index,
                    onSet: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
