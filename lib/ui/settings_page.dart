import 'package:flutter/material.dart';
import 'package:gps_mock/models/map_style.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/services/update_service.dart';
import 'package:gps_mock/ui/offline_maps_page.dart';
import 'package:gps_mock/ui/permissions_sheet.dart';
import 'package:gps_mock/ui/theme.dart';
import 'package:gps_mock/ui/update_dialog.dart';
import 'package:gps_mock/utils/constants.dart';
import 'package:provider/provider.dart';

/// App-wide settings: how it looks, which basemap it draws, what it keeps on
/// the device, and the Android-side setup mocking depends on.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final UpdateService _updates = UpdateService();
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final version = await _updates.platform.installedVersion();
    if (mounted) setState(() => _version = version);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              pinned: true,
              title: const Text('Settings'),
              backgroundColor: theme.colorScheme.surface,
            ),
            SliverList.list(
              children: [
                _SetupCard(appState: appState),

                _Section(title: 'Appearance'),
                _Tile(
                  icon: Icons.brightness_6_outlined,
                  title: 'Theme',
                  subtitle: switch (appState.themeMode) {
                    ThemeMode.system => 'Follow the system',
                    ThemeMode.light => 'Always light',
                    ThemeMode.dark => 'Always dark',
                  },
                  onTap: () => _pickTheme(context, appState),
                ),

                _Section(title: 'Map'),
                _Tile(
                  icon: Icons.layers_outlined,
                  title: 'Map style',
                  subtitle: MapStyle.byId(appState.mapStyle).name,
                  onTap: () => _pickMapStyle(context, appState),
                ),
                _Tile(
                  icon: Icons.cloud_download_outlined,
                  title: 'Offline maps',
                  subtitle: 'Keep cities, states or routes on the device',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OfflineMapsPage()),
                  ),
                ),

                _Section(title: 'Mocking'),
                _Tile(
                  icon: Icons.checklist,
                  title: 'Setup & permissions',
                  subtitle: 'Mock location app, location, notifications, '
                      'battery',
                  onTap: () => PermissionsSheet.show(context),
                ),
                _Tile(
                  icon: Icons.developer_mode,
                  title: 'Developer options',
                  subtitle: 'Open Android developer settings',
                  onTap: appState.openSettings,
                ),

                _Section(title: 'Data'),
                _Tile(
                  icon: Icons.history,
                  title: 'Clear mock history',
                  subtitle: appState.history.isEmpty
                      ? 'Nothing recorded'
                      : '${appState.history.length} sessions recorded',
                  onTap: appState.history.isEmpty
                      ? null
                      : () => _confirm(
                            context,
                            'Clear mock history?',
                            'Every recorded session is removed.',
                            appState.clearHistory,
                          ),
                ),
                _Tile(
                  icon: Icons.search_off,
                  title: 'Clear recent searches',
                  subtitle: appState.recentSearches.isEmpty
                      ? 'No recent searches'
                      : '${appState.recentSearches.length} remembered',
                  onTap: appState.recentSearches.isEmpty
                      ? null
                      : appState.clearRecentSearches,
                ),

                _Section(title: 'Updates'),
                _Tile(
                  icon: Icons.system_update,
                  title: 'Check for updates',
                  subtitle: _version.isEmpty
                      ? 'Fetches the latest GitHub release'
                      : 'Installed version $_version',
                  onTap: () => checkForUpdatesInteractively(context, _updates),
                ),
                _Tile(
                  icon: Icons.new_releases_outlined,
                  title: 'Release notes',
                  subtitle: 'Every published release on GitHub',
                  onTap: () =>
                      openProjectLink(context, AppConstants.releasesUrl),
                ),

                _Section(title: 'Developer'),
                _DeveloperCard(version: _version),
                _Tile(
                  icon: Icons.code,
                  title: 'Source code',
                  subtitle: 'github.com/Sriharan-S/gps-mock',
                  onTap: () =>
                      openProjectLink(context, AppConstants.repositoryUrl),
                ),
                _Tile(
                  icon: Icons.person_outline,
                  title: AppConstants.developerName,
                  subtitle: 'github.com/Sriharan-S',
                  onTap: () =>
                      openProjectLink(context, AppConstants.developerGithub),
                ),
                _Tile(
                  icon: Icons.bug_report_outlined,
                  title: 'Report an issue',
                  subtitle: 'Open a ticket on GitHub',
                  onTap: () => openProjectLink(context, AppConstants.issuesUrl),
                ),

                _Section(title: 'About'),
                _Tile(
                  icon: Icons.info_outline,
                  title: 'About GPS Mock',
                  subtitle: _version.isEmpty ? 'Licences and credits' : 'Version $_version',
                  onTap: () => _showAbout(context),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTheme(BuildContext context, AppState appState) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Theme',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            RadioGroup<ThemeMode>(
              groupValue: appState.themeMode,
              onChanged: (value) {
                if (value == null) return;
                appState.setThemeMode(value);
                Navigator.pop(sheetContext);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(switch (mode) {
                        ThemeMode.system => 'Follow the system',
                        ThemeMode.light => 'Light',
                        ThemeMode.dark => 'Dark',
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMapStyle(BuildContext context, AppState appState) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Map style',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            RadioGroup<MapStyleId>(
              groupValue: appState.mapStyle,
              onChanged: (value) {
                if (value == null) return;
                appState.setMapStyle(value);
                Navigator.pop(sheetContext);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final style in MapStyle.all)
                    RadioListTile<MapStyleId>(
                      value: style.id,
                      title: Text(style.name),
                      subtitle: Text(style.description),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await action();
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'GPS Mock',
      applicationVersion: _version.isEmpty ? null : 'Version $_version',
      applicationIcon: const Icon(Icons.location_pin, size: 40),
      children: const [
        Text(
          'GPS Mock spoofs your device location and simulates trips along '
          'real roads. It is the testing companion for My Globe, a maps & '
          'navigation project.\n\n'
          'Maps by OpenStreetMap contributors and other free providers, '
          'search by Photon, routing by OSRM — all free and keyless.\n\n'
          'Built by ${AppConstants.developerName}.\n'
          '${AppConstants.repositoryUrl}',
        ),
      ],
    );
  }
}

/// The developer's card: who made this and where to find the project.
class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openProjectLink(context, AppConstants.developerGithub),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    'SS',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConstants.developerName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Developer · GPS Mock'
                        '${version.isEmpty ? '' : ' $version'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.code, size: 16),
                            label: const Text('Repository'),
                            onPressed: () => openProjectLink(
                              context,
                              AppConstants.repositoryUrl,
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.person_outline, size: 16),
                            label: const Text('GitHub'),
                            onPressed: () => openProjectLink(
                              context,
                              AppConstants.developerGithub,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Surfaces the one bit of setup without which nothing works at all.
class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = appState.isMockLocationApp == true;
    final scheme = theme.colorScheme;
    final status = theme.status;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: ready ? status.liveContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => PermissionsSheet.show(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  ready ? Icons.verified_rounded : Icons.warning_amber_rounded,
                  color: ready ? status.onLiveContainer : scheme.onErrorContainer,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ready ? 'Ready to mock' : 'Setup needed',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ready
                              ? status.onLiveContainer
                              : scheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ready
                            ? 'GPS Mock is selected as the mock location app.'
                            : 'Select GPS Mock as the mock location app in '
                                'Developer Options.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ready
                              ? status.onLiveContainer
                              : scheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: ready ? status.onLiveContainer : scheme.onErrorContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: ListTile(
        enabled: enabled,
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: scheme.surfaceContainerHighest,
          child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: enabled ? const Icon(Icons.chevron_right) : null,
      ),
    );
  }
}
