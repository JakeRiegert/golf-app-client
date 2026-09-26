// Smoke test for the create-tournament screen. Deliberately does not pump the full GolfApp
// (that requires Amplify.configure, which needs real deployed backend config) -- just checks
// CreateTournamentScreen's own UI renders, since it doesn't touch Amplify until the button is
// pressed. Real integration coverage (calling the actual mutation) belongs in a later
// integration_test, not a widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:golf_app_client/main.dart';

void main() {
  testWidgets('shows a name field and a create button', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CreateTournamentScreen()),
    );

    expect(find.text('Tournament name'), findsOneWidget);
    expect(find.text('Create Tournament'), findsOneWidget);
  });
}
