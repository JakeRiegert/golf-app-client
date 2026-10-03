import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';

import 'amplifyconfiguration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureAmplify();
  runApp(const GolfApp());
}

Future<void> _configureAmplify() async {
  try {
    await Amplify.addPlugins([
      AmplifyAuthCognito(),
      AmplifyAPI(),
    ]);
    await Amplify.configure(amplifyconfig);
  } on Exception catch (e) {
    // Safe to ignore "already configured" on hot restart; anything else is worth seeing.
    safePrint('Amplify configure error: $e');
  }
}

class GolfApp extends StatelessWidget {
  const GolfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Authenticator(
      child: MaterialApp(
        title: 'Golf Live Scoring',
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        builder: Authenticator.builder(),
        home: const CreateTournamentScreen(),
      ),
    );
  }
}

class CreateTournamentScreen extends StatefulWidget {
  const CreateTournamentScreen({super.key});

  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final _nameController = TextEditingController();
  bool _isSubmitting = false;
  String? _lastCreatedName;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _upsertPlayerProfile();
  }

  static const _upsertPlayerProfileMutation = '''
    mutation UpsertPlayerProfile {
      upsertPlayerProfile {
        id
        createdAt
        updatedAt
      }
    }
  ''';

  // Fire-and-forget identity sync, not a user-facing action -- seeds/touches this caller's
  // Player row on every sign-in (see docs/blueprint.md: auto-called once on first sign-in,
  // idempotent so re-firing on later sign-ins is harmless). No displayName/avatarUrl seeding
  // yet -- see the players Lambda plan for why that's deliberately deferred.
  Future<void> _upsertPlayerProfile() async {
    try {
      final request = GraphQLRequest<String>(document: _upsertPlayerProfileMutation);
      await Amplify.API.mutate(request: request).response;
    } on Exception catch (e) {
      safePrint('upsertPlayerProfile error: $e');
    }
  }

  static const _createTournamentMutation = '''
    mutation CreateTournament(\$name: String!) {
      createTournament(name: \$name) {
        id
        name
        createdAt
        organizerId
      }
    }
  ''';

  Future<void> _createTournament() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final request = GraphQLRequest<String>(
        document: _createTournamentMutation,
        variables: {'name': name},
      );
      final response = await Amplify.API.mutate(request: request).response;

      if (response.hasErrors) {
        setState(() => _errorMessage = response.errors.first.message);
      } else {
        setState(() {
          _lastCreatedName = name;
          _nameController.clear();
        });
      }
    } on Exception catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Tournament'),
        actions: const [SignOutButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tournament name',
                    hintText: 'e.g. Myrtle Beach Trip 2026',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _createTournament(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isSubmitting ? null : _createTournament,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Tournament'),
                ),
                if (_lastCreatedName != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Created "$_lastCreatedName" — saved to DynamoDB via AppSync.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
