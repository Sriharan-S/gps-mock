import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:provider/provider.dart';

/// Lets the user import a route either by choosing a GPX/coordinate file or
/// by pasting its contents, and turns it into a planned route ready to
/// simulate. Returns true once a route was successfully imported.
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
  bool _picking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Opens the system file picker, reads the chosen file and imports it. Uses
  /// the file name as the route label.
  Future<void> _pickFile() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        // Some Android providers don't report a GPX MIME type, so accept any
        // file and validate its contents instead of filtering by extension.
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return; // cancelled
      final file = result.files.single;

      String? content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.readStream != null) {
        final chunks = <int>[];
        await for (final chunk in file.readStream!) {
          chunks.addAll(chunk);
        }
        content = utf8.decode(chunks, allowMalformed: true);
      }
      if (content == null || content.trim().isEmpty) {
        setState(() => _error = "Could not read the selected file.");
        return;
      }

      if (!mounted) return;
      final error = context.read<AppState>().importRoute(
            content,
            sourceName: file.name,
          );
      if (error != null) {
        // Surface the file's content so the user can inspect/fix it.
        _controller.text = content;
        setState(() => _error = error);
        return;
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = "Could not open the file picker.");
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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
      setState(() => _error = "Choose a file or paste a GPX / coordinate list.");
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
              "Choose a GPX or .txt file, or paste its contents below — "
              "a GPX track/route or a list of coordinates, one "
              "\"latitude, longitude\" per line. The route is drawn on the map "
              "so you can simulate driving it.",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _picking ? null : _pickFile,
              icon: _picking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open),
              label: Text(_picking ? "Opening…" : "Choose file"),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text("or paste", style: theme.textTheme.bodySmall),
                ),
                const Expanded(child: Divider()),
              ],
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
