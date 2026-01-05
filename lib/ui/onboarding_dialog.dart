import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gps_mock/providers/app_state.dart';

class OnboardingDialog extends StatelessWidget {
  const OnboardingDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Enable Mock Location"),
      content: const Text(
        "To use this app, you must enable 'Mock Location' in Developer Settings.\n\n"
        "1. Tap 'Open Settings' below.\n"
        "2. Find 'Select mock location app'.\n"
        "3. Select 'GPS Mock'.",
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
