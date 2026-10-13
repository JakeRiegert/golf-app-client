// Smoke test for the sign-in screen. Pumps SignInScreen directly rather than the full GolfApp
// (which needs Firebase.initializeApp against the real project) -- the screen doesn't touch
// FirebaseAuth until a button is pressed. Real sign-in coverage belongs in the Firebase
// emulator-backed tests, not a widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:golf_app_client/sign_in_screen.dart';

void main() {
  testWidgets('shows Google sign-in first, with an email/password fallback',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Need an account? Create one'), findsOneWidget);
  });
}
