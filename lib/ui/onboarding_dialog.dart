import 'package:flutter/material.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:provider/provider.dart';

class OnboardingDialog extends StatelessWidget {
  const OnboardingDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text("Set up mock location"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "To spoof your GPS position, Android requires GPS Mock to be "
            "selected as the mock location app:",
          ),
          const SizedBox(height: 12),
          const Text(
            "1. Tap 'Open Settings' below.\n"
            "2. Find 'Select mock location app'.\n"
            "3. Choose 'GPS Mock'.",
          ),
          const SizedBox(height: 16),
          Text(
            "GPS Mock is a testing companion for My Globe, a maps & "
            "navigation app — use it to simulate positions and routes "
            "while developing location features.",
            style: textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Later"),
        ),
        FilledButton(
          onPressed: () {
            context.read<AppState>().openSettings();
            Navigator.pop(context);
          },
          child: const Text("Open Settings"),
        ),
      ],
    );
  }
}
