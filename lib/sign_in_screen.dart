import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Minimal sign-in: "Continue with Google" first (fewest clicks, no account creation),
// email/password as the fallback. Deliberately not firebase_ui_auth -- Google on web there
// needs a separately configured client ID, and this covers everything we need today.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isCreatingAccount = false;
  bool _isBusy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException code=${e.code} message=${e.message}');
      if (mounted) setState(() => _errorMessage = '${e.code}: ${e.message ?? '(no message)'}');
    } catch (e) {
      debugPrint('Sign-in failed: $e');
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _signInWithGoogle() => _run(() async {
        final provider = GoogleAuthProvider();
        if (kIsWeb) {
          await FirebaseAuth.instance.signInWithPopup(provider);
        } else {
          await FirebaseAuth.instance.signInWithProvider(provider);
        }
      });

  Future<void> _submitEmail() => _run(() async {
        final email = _emailController.text.trim();
        final password = _passwordController.text;
        if (_isCreatingAccount) {
          await FirebaseAuth.instance
              .createUserWithEmailAndPassword(email: email, password: password);
        } else {
          await FirebaseAuth.instance
              .signInWithEmailAndPassword(email: email, password: password);
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Golf Live Scoring',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: _isBusy ? null : _signInWithGoogle,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Continue with Google'),
                  ),
                ),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _isBusy ? null : _submitEmail(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isBusy ? null : _submitEmail,
                  child: Text(_isCreatingAccount ? 'Create account' : 'Sign in'),
                ),
                TextButton(
                  onPressed: _isBusy
                      ? null
                      : () => setState(() => _isCreatingAccount = !_isCreatingAccount),
                  child: Text(
                    _isCreatingAccount
                        ? 'Already have an account? Sign in'
                        : 'Need an account? Create one',
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
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
