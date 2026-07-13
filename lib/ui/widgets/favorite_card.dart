import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gps_mock/models/location_item.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/utils/constants.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

/// A saved-location card with a mini OSM preview, used both by the Saved tab
/// and the favorites picker sheet.
class FavoriteCard extends StatelessWidget {
  final LocationItem item;
  final int index;
  final VoidCallback onSet;

  const FavoriteCard({
    super.key,
    required this.item,
    required this.index,
    required this.onSet,
  });

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
          SizedBox(
            width: 110,
            height: 116,
            child: ExcludeSemantics(child: _MapThumbnail(item: item)),
          ),
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
                        child: FilledButton(
                          onPressed: onSet,
                          style: FilledButton.styleFrom(
                            shape: const StadiumBorder(),
                            minimumSize: const Size(0, 44),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text("Set"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: "Delete favorite",
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => _delete(context),
                        icon: const Icon(Icons.delete_outline, size: 20),
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

/// Non-interactive OSM mini-map centred on the favorite — fully free, no
/// API key.
class _MapThumbnail extends StatelessWidget {
  final LocationItem item;

  const _MapThumbnail({required this.item});

  @override
  Widget build(BuildContext context) {
    final point = LatLng(item.latitude, item.longitude);
    return IgnorePointer(
      child: FlutterMap(
        options: MapOptions(
          initialCenter: point,
          initialZoom: 14,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: AppConstants.osmTileUrl,
            userAgentPackageName: AppConstants.tileUserAgentPackage,
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: point,
                width: 22,
                height: 22,
                alignment: Alignment.topCenter,
                child: Icon(
                  Icons.location_pin,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
