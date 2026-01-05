import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/utils/constants.dart';

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
              color: Colors.grey.withOpacity(0.3),
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
              child: Text("No favorites yet"),
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
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [
                        // Left Thumbnail (1:1 Ratio)
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: ColoredBox(
                            color: Colors.grey.shade200,
                            child: Image.network(
                              AppConstants.getStaticMapUrl(
                                item.latitude,
                                item.longitude,
                              ),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.map,
                                  size: 30,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Right Content
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
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 32,
                                        child: ElevatedButton(
                                          onPressed: () {
                                            final latLng = LatLng(
                                              item.latitude,
                                              item.longitude,
                                            );
                                            context
                                                .read<AppState>()
                                                .updateLocation(
                                                  latLng,
                                                  address: item.address,
                                                );
                                            Navigator.pop(context);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            shape: const StadiumBorder(),
                                            padding: EdgeInsets.zero,
                                          ),
                                          child: const Text("Set"),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: SizedBox(
                                        height: 32,
                                        child: ElevatedButton(
                                          onPressed: () {
                                            context
                                                .read<AppState>()
                                                .removeFavorite(item);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            shape: const StadiumBorder(),
                                            padding: EdgeInsets.zero,
                                          ),
                                          child: const Text("Delete"),
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
                },
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
