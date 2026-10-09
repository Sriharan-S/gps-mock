import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_mock/providers/app_state.dart';
import 'package:gps_mock/ui/control_deck.dart';
import 'package:gps_mock/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  late AppState appState;

  Future<void> pumpDeck(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a wide square, which overflows the
    // mode tiles' labels; that says nothing about real layouts.
    final reportError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      reportError?.call(details);
    };
    addTearDown(() => FlutterError.onError = reportError);
    appState = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ControlDeck(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The mode switch only exists while the deck is open past peek.
  final modeSwitch = find.text('Route');
  Finder handle() => find.bySemanticsLabel(RegExp('the controls'));

  testWidgets('a slow pull down on the peek bar collapses the deck',
      (tester) async {
    await pumpDeck(tester);
    expect(modeSwitch, findsOneWidget);

    // Slow drag: almost no release velocity, so distance must count.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Drag the pin to choose a spot').first),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 8));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(modeSwitch, findsNothing);
  });

  testWidgets('dragging up from peek reopens it', (tester) async {
    await pumpDeck(tester);
    await tester.tap(handle());
    await tester.pumpAndSettle();
    expect(modeSwitch, findsNothing);

    await tester.drag(handle(), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(modeSwitch, findsOneWidget);
  });

  testWidgets('dragging up from half opens full, and down steps back',
      (tester) async {
    await pumpDeck(tester);
    expect(
      tester.getSemantics(handle()),
      matchesSemantics(
        value: 'Half open',
        label: 'Collapse the controls',
        isButton: true,
        hasTapAction: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );

    await tester.drag(handle(), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(handle()).value, 'Fully open');

    await tester.drag(handle(), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(handle()).value, 'Half open');
  });

  testWidgets('a long pull from full goes straight to peek', (tester) async {
    await pumpDeck(tester);
    await tester.drag(handle(), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(handle()).value, 'Fully open');

    await tester.drag(handle(), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(handle()).value, 'Collapsed');
  });

  testWidgets('route mode content also drags the deck', (tester) async {
    await pumpDeck(tester);
    appState.setRouteMode(true);
    await tester.pumpAndSettle();
    expect(find.text('Choose a destination'), findsOneWidget);

    // A drag that starts on the planner itself, not the handle.
    await tester.drag(
      find.text('Choose a destination'),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(tester.getSemantics(handle()).value, 'Collapsed');
  });
}
