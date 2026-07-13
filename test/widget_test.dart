import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_mock/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App shows splash screen on startup', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MockGpsApp());

    // Verify that the MaterialApp renders
    expect(find.byType(MaterialApp), findsOneWidget);

    // Verify splash screen is shown with logo
    expect(find.byType(Image), findsOneWidget);

    // Dispose the tree, then let the splash minimum-display timer fire
    // harmlessly so no timers are pending when the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
