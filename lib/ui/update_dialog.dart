import 'package:flutter/material.dart';
import 'package:gps_mock/services/update_service.dart';
import 'package:gps_mock/utils/constants.dart';

/// Offers a newer release: update now, or later.
///
/// Ticking "don't remind me again today" snoozes the prompt until tomorrow —
/// the app still checks on the next launch, it just stays quiet.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.release,
    required this.service,
    required this.installedVersion,
    this.allowSnooze = true,
    this.comparable = true,
  });

  final AppRelease release;
  final UpdateService service;
  final String installedVersion;

  /// False when the release tag can't be measured against the installed
  /// build, so the dialog offers it rather than asserting you are behind.
  final bool comparable;

  /// False when the user asked to check for updates themselves — snoozing a
  /// prompt you opened on purpose makes no sense.
  final bool allowSnooze;

  static Future<void> show(
    BuildContext context, {
    required AppRelease release,
    required UpdateService service,
    required String installedVersion,
    bool allowSnooze = true,
    bool comparable = true,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(
        release: release,
        service: service,
        installedVersion: installedVersion,
        allowSnooze: allowSnooze,
        comparable: comparable,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _snooze = false;
  bool _downloading = false;
  double _progress = 0;
  int _received = 0;
  int _total = 0;
  String? _error;

  Future<void> _later() async {
    if (_snooze) await widget.service.snoozeForToday();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _update() async {
    final release = widget.release;

    // No APK attached to the release — send the user to the page instead of
    // pretending we can install it.
    if (!release.hasApk) {
      await widget.service.platform.openUrl(release.pageUrl);
      if (mounted) Navigator.pop(context);
      return;
    }

    // Android needs explicit consent before this app may install packages.
    if (!await widget.service.platform.canInstallPackages()) {
      if (!mounted) return;
      setState(() {
        _error = 'Android needs permission to install apps from GPS Mock. '
            'Grant it, then tap Update again.';
      });
      await widget.service.platform.requestInstallPermission();
      return;
    }

    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });

    try {
      final path = await widget.service.downloadApk(
        release,
        onProgress: (progress, received, total) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _received = received;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      await widget.service.platform.installApk(path);
      // The installer takes over from here; record the tag so the check stops
      // offering this release once the user comes back.
      await widget.service.markReleaseInstalled(release.tag);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Could not download the update: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final release = widget.release;

    return AlertDialog(
      icon: const Icon(Icons.system_update),
      title: Text(
        widget.comparable ? 'Update to ${release.version}?' : 'Update available',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.comparable
                  ? 'You have ${widget.installedVersion.isEmpty ? 'an older build' : widget.installedVersion}'
                      '${release.hasApk ? ' · ${release.sizeLabel} download' : ''}'
                  : '${release.name} — '
                      'Installed: ${widget.installedVersion.isEmpty ? 'unknown' : widget.installedVersion}'
                      '${release.hasApk ? ' · ${release.sizeLabel} download' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (release.notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    release.notes,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            if (!release.hasApk) ...[
              const SizedBox(height: 14),
              Text(
                'This release has no APK attached, so the download page will '
                'open in your browser.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _total > 0 ? _progress : null,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _total > 0
                    ? 'Downloading ${(_progress * 100).round()}% · '
                        '${_bytes(_received)} of ${_bytes(_total)}'
                    : 'Downloading…',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            if (widget.allowSnooze && !_downloading) ...[
              const SizedBox(height: 6),
              // Padding trimmed so the row reads as one tappable line.
              CheckboxListTile(
                value: _snooze,
                onChanged: (value) => setState(() => _snooze = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  "Don't remind me again today",
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading
              ? null
              : () => widget.service.platform.openUrl(release.pageUrl),
          child: const Text('Details'),
        ),
        TextButton(
          onPressed: _downloading ? null : _later,
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: _downloading ? null : _update,
          child: Text(release.hasApk ? 'Update' : 'Open page'),
        ),
      ],
    );
  }

  static String _bytes(int value) {
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (value >= 1024) return '${(value / 1024).round()} KB';
    return '$value B';
  }
}

/// Runs the startup check and shows the prompt when something newer exists.
///
/// Silent by design: no network, no dialog and no error surface when the user
/// has snoozed for the day or the check simply fails.
Future<void> maybePromptForUpdate(
  BuildContext context,
  UpdateService service,
) async {
  if (await service.isSnoozed()) return;
  final release = await service.checkForUpdate();
  if (release == null || !context.mounted) return;
  final installed = await service.platform.installedVersion();
  final comparable = await service.isComparable(release);
  if (!context.mounted) return;
  await UpdateDialog.show(
    context,
    release: release,
    service: service,
    installedVersion: installed,
    comparable: comparable,
  );
}

/// The manual "check for updates" path, which reports both outcomes.
Future<void> checkForUpdatesInteractively(
  BuildContext context,
  UpdateService service,
) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(content: Text('Checking for updates…')),
  );
  final release = await service.checkForUpdate(force: true);
  if (!context.mounted) return;
  if (release == null) {
    final installed = await service.platform.installedVersion();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          installed.isEmpty
              ? 'You are on the latest version.'
              : 'GPS Mock $installed is the latest version.',
        ),
      ),
    );
    return;
  }
  final installed = await service.platform.installedVersion();
  final comparable = await service.isComparable(release);
  if (!context.mounted) return;
  await UpdateDialog.show(
    context,
    release: release,
    service: service,
    installedVersion: installed,
    allowSnooze: false,
    comparable: comparable,
  );
}

/// Opens a project link, falling back to a message when no browser handles it.
Future<void> openProjectLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await PlatformClient().openUrl(url);
  if (opened || !context.mounted) return;
  messenger.showSnackBar(
    SnackBar(content: Text('Could not open $url')),
  );
}

/// Shorthand for the repository, used from more than one place.
String get repositoryUrl => AppConstants.repositoryUrl;
