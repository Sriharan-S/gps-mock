import 'package:flutter/material.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:provider/provider.dart';

/// Dialog for naming and saving the current map location as a favorite.
class SaveFavoriteDialog extends StatefulWidget {
  const SaveFavoriteDialog({super.key});

  @override
  State<SaveFavoriteDialog> createState() => _SaveFavoriteDialogState();
}

class _SaveFavoriteDialogState extends State<SaveFavoriteDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: context.read<AppState>().currentAddress,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final textTheme = Theme.of(context).textTheme;
    final location = appState.currentLocation;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("New Favorite", style: textTheme.titleLarge),
                IconButton(
                  tooltip: "Close",
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoField(
              icon: Icons.location_on_outlined,
              label: "Address",
              value: appState.currentAddress,
            ),
            const SizedBox(height: 12),
            _InfoField(
              icon: Icons.map_outlined,
              label: "Coordinates",
              value: location == null
                  ? "—"
                  : "${location.latitude.toStringAsFixed(6)}, "
                        "${location.longitude.toStringAsFixed(6)}",
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: "Name",
                hintText: "Enter a name…",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      appState.addFavorite(_nameController.text);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Favorite saved")),
                      );
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text("Save"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoField({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colorScheme.outline),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
