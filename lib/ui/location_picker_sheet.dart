import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/services/search_service.dart';
import 'package:provider/provider.dart';

class PickedLocation {
  final LatLng location;
  final String label;
  const PickedLocation(this.location, this.label);
}

/// Bottom sheet used by the route planner to pick an endpoint via search,
/// the current map pin, or a saved favorite. Pops with a [PickedLocation].
class LocationPickerSheet extends StatefulWidget {
  final String title;
  const LocationPickerSheet({super.key, required this.title});

  static Future<PickedLocation?> show(BuildContext context, String title) {
    return showModalBottomSheet<PickedLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LocationPickerSheet(title: title),
    );
  }

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final SearchService _searchService = SearchService();
  final TextEditingController _searchController = TextEditingController();
  String _lastQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return Padding(
      // Keep the sheet above the keyboard while searching.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
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
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TypeAheadField<PlaceSuggestion>(
              controller: _searchController,
              debounceDuration: const Duration(milliseconds: 350),
              builder: (context, controller, focusNode) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: "Search places…",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    isDense: true,
                  ),
                );
              },
              suggestionsCallback: (pattern) async {
                _lastQuery = pattern.trim();
                if (_lastQuery.length < 3) return const <PlaceSuggestion>[];
                return _searchService.search(
                  pattern,
                  near: context.read<AppState>().currentLocation,
                );
              },
              emptyBuilder: (context) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _lastQuery.length < 3
                      ? "Type at least 3 characters to search"
                      : "No places found",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              itemBuilder: (context, suggestion) => ListTile(
                dense: true,
                leading: const Icon(Icons.place_outlined),
                title: Text(
                  suggestion.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: suggestion.description.isEmpty
                    ? null
                    : Text(
                        suggestion.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              onSelected: (suggestion) {
                Navigator.pop(
                  context,
                  PickedLocation(suggestion.location, suggestion.name),
                );
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.center_focus_strong),
              title: const Text("Use current map pin"),
              subtitle: Text(
                appState.currentAddress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              enabled: appState.currentLocation != null,
              onTap: appState.currentLocation == null
                  ? null
                  : () => Navigator.pop(
                      context,
                      PickedLocation(
                        appState.currentLocation!,
                        appState.currentAddress,
                      ),
                    ),
            ),
            if (appState.favorites.isNotEmpty) ...[
              const Divider(),
              Text(
                "Favorites",
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: appState.favorites.length,
                  itemBuilder: (context, index) {
                    final item = appState.favorites[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.favorite, size: 18),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        PickedLocation(
                          LatLng(item.latitude, item.longitude),
                          item.name,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
