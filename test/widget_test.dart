import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/main.dart';

void main() {
  testWidgets('MyApp renders the player screen app bar', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Музыка'), findsOneWidget);
  });
}
