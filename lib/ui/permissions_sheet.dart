import 'package:flutter/material.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

/// "Setup & permissions" checklist: everything GPS Mock needs to work
/// reliably, with one-tap fixes.
class PermissionsSheet extends StatefulWidget {
  const PermissionsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const PermissionsSheet(),
    );
  }

  @override
  State<PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<PermissionsSheet>
    with WidgetsBindingObserver {
  bool? _location;
  bool? _notifications;
  bool? _battery;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from a system settings screen — re-check everything.
    if (state == AppLifecycleState.resumed) {
      _refresh();
      context.read<AppState>().refreshMockLocationCheck();
    }
  }

  Future<void> _refresh() async {
    final location = await Permission.location.isGranted;
    final notifications = await Permission.notification.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    if (!mounted) return;
    setState(() {
      _location = location;
      _notifications = notifications;
      _battery = battery;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Container(
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
          Text(
            "Setup & permissions",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            "Everything GPS Mock needs to mock reliably — including "
            "long route simulations in the background.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            icon: Icons.developer_mode,
            title: "Mock location app",
            subtitle: "Select GPS Mock in Developer Options",
            granted: appState.isMockLocationApp,
            actionLabel: "Open settings",
            onFix: () => context.read<AppState>().openSettings(),
          ),
          _PermissionRow(
            icon: Icons.location_on_outlined,
            title: "Location",
            subtitle: "Needed to show your real position",
            granted: _location,
            onFix: () async {
              await Permission.location.request();
              _refresh();
            },
          ),
          _PermissionRow(
            icon: Icons.notifications_outlined,
            title: "Notifications",
            subtitle: "Mocking status and problem alerts",
            granted: _notifications,
            onFix: () async {
              await Permission.notification.request();
              _refresh();
            },
          ),
          _PermissionRow(
            icon: Icons.battery_saver_outlined,
            title: "No battery optimization",
            subtitle: "Keeps long route simulations running in the background",
            granted: _battery,
            onFix: () async {
              await Permission.ignoreBatteryOptimizations.request();
              _refresh();
            },
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool? granted;
  final String actionLabel;
  final VoidCallback onFix;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    this.actionLabel = "Allow",
    required this.onFix,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: granted == true
          ? Icon(Icons.check_circle, color: Colors.green.shade600)
          : FilledButton.tonal(
              onPressed: onFix,
              child: Text(granted == null ? "Check" : actionLabel),
            ),
    );
  }
}
