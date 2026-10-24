import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'home_screen.dart';
import 'sign_in_screen.dart';

// Run with --dart-define=USE_EMULATORS=true to talk to the local Firebase emulators (Auth,
// Firestore, Functions) instead of the real project. Off by default, so a normal build can
// never be pointed at localhost by accident.
const bool useEmulators = bool.fromEnvironment('USE_EMULATORS');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator('localhost', 5001);
  }
  runApp(const GolfApp());
}

class GolfApp extends StatelessWidget {
  const GolfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Golf Live Scoring',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      // Inside the app (not around it) so the banner has a Directionality ancestor.
      builder: (context, child) => useEmulators
          ? Banner(
              message: 'LOCAL EMULATOR',
              location: BannerLocation.bottomStart,
              color: Colors.deepOrange,
              child: child!,
            )
          : child!,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        return user == null ? const SignInScreen() : HomeScreen(user: user);
      },
    );
  }
}
