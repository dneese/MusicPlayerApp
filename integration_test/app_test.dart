import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:music_player_app/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and renders the player UI without crashing',
      (WidgetTester tester) async {
    app.main();

    // Give the app time to render the first frame (avoids pumpAndSettle,
    // which hangs on looping animations: spinner / visualizer).
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // The AppBar title should be rendered once the app has launched.
    expect(find.text('Музыка'), findsOneWidget);

    // The app is responsive: tapping the theme toggle should not crash.
    final paletteButton = find.byIcon(Icons.palette);
    expect(paletteButton, findsOneWidget);
    await tester.tap(paletteButton);
    await tester.pump(const Duration(milliseconds: 300));

    // Still alive after the tap.
    expect(find.text('Музыка'), findsOneWidget);
  });
}
