import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:provider/provider.dart';

/// Lets the user paste a GPX track or a list of coordinates and turn it into
/// a planned route ready to simulate. Returns true once a route was
/// successfully imported.
class ImportRouteDialog extends StatefulWidget {
  const ImportRouteDialog({super.key});

  /// Shows the dialog. Resolves to true when a route was imported.
  static Future<bool> show(BuildContext context) async {
    final imported = await showDialog<bool>(
      context: context,
      builder: (_) => const ImportRouteDialog(),
    );
    return imported ?? false;
  }

  @override
  State<ImportRouteDialog> createState() => _ImportRouteDialogState();
}

class _ImportRouteDialogState extends State<ImportRouteDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    setState(() => _error = null);
  }

  void _import() {
    final content = _controller.text;
    if (content.trim().isEmpty) {
      setState(() => _error = "Paste a GPX track or a list of coordinates.");
      return;
    }
    final error = context.read<AppState>().importRoute(content);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text("Import route"),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Paste the contents of a GPX file, or a list of coordinates — "
              "one \"latitude, longitude\" per line. The route is drawn on the "
              "map so you can simulate driving it.",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 8,
              minLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                hintText: "48.2082, 16.3738\n"
                    "48.2100, 16.3800\n"
                    "48.2150, 16.3900\n"
                    "…or <gpx>…</gpx>",
                border: const OutlineInputBorder(),
                errorText: _error,
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text("Paste from clipboard"),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _import,
          child: const Text("Import"),
        ),
      ],
    );
  }
}
