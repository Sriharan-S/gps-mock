import 'package:flutter/material.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/utils/constants.dart';
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
                  return _FavoriteCard(item: item, index: index);
                },
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  final LocationItem item;
  final int index;

  const _FavoriteCard({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // Left thumbnail (1:1 ratio)
          SizedBox(
            width: 108,
            height: 108,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Image.network(
                AppConstants.getStaticMapUrl(item.latitude, item.longitude),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.map, size: 30, color: Colors.grey),
                ),
              ),
            ),
          ),
          // Right content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.address,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "${item.latitude.toStringAsFixed(4)}, ${item.longitude.toStringAsFixed(4)}",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: FilledButton(
                            onPressed: () {
                              // The home screen moves the map to the result.
                              Navigator.pop(context, item);
                            },
                            style: FilledButton.styleFrom(
                              shape: const StadiumBorder(),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text("Set"),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 40,
                        width: 48,
                        child: IconButton.outlined(
                          tooltip: "Delete favorite",
                          onPressed: () => _delete(context),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          style: IconButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _delete(BuildContext context) {
    final appState = context.read<AppState>();
    final removedIndex = index;
    final removedItem = item;
    appState.removeFavorite(item);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${removedItem.name}"'),
        action: SnackBarAction(
          label: "UNDO",
          onPressed: () => appState.insertFavorite(removedIndex, removedItem),
        ),
      ),
    );
  }
}
