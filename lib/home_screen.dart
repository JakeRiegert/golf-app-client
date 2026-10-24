import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'tournaments_panel.dart';

// Signed-in home. For now this is the first slice of the debug harness: it calls the
// upsertPlayerProfile Cloud Function once on arrival (creating or touching this user's profile),
// shows the profile live from Firestore, and lets you edit the display name through the same
// function. Reads come straight from Firestore (live listeners); every write goes through a
// function, never directly from the client.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  final User user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _saving = false;
  String? _status;
  String? _error;

  HttpsCallable get _upsert =>
      FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('upsertPlayerProfile');

  DocumentReference<Map<String, dynamic>> get _profileDoc =>
      FirebaseFirestore.instance.collection('players').doc(widget.user.uid);

  DocumentReference<Map<String, dynamic>> get _privateDoc =>
      _profileDoc.collection('private').doc('profile');

  @override
  void initState() {
    super.initState();
    _syncProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _syncProfile() async {
    try {
      await _upsert.call();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = '${e.code}: ${e.message}');
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text;
    setState(() {
      _saving = true;
      _status = null;
      _error = null;
    });
    try {
      await _upsert.call({'displayName': name});
      if (mounted) setState(() => _status = 'Saved.');
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = '${e.code}: ${e.message}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatTime(Object? value) {
    if (value is Timestamp) return value.toDate().toLocal().toString();
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Golf Live Scoring'),
        actions: [
          TextButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Your profile', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Live from Firestore. Edits go through the upsertPlayerProfile function.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _profileDoc.snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data();
                    if (data == null) {
                      return const Text('Creating your profile...');
                    }
                    if (!_nameFocus.hasFocus) {
                      _nameController.text = (data['displayName'] as String?) ?? '';
                    }
                    final meta = snapshot.data!.metadata;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _nameController,
                          focusNode: _nameFocus,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _saving ? null : _saveName(),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _saving ? null : _saveName,
                          child: const Text('Save display name'),
                        ),
                        const SizedBox(height: 16),
                        Text('Avatar URL: ${data['avatarUrl'] ?? '-'}'),
                        Text('Created: ${_formatTime(data['createdAt'])}'),
                        Text('Updated: ${_formatTime(data['updatedAt'])}'),
                        Text(
                          'Snapshot: ${meta.isFromCache ? 'from cache' : 'from server'}'
                          '${meta.hasPendingWrites ? ', pending write' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _privateDoc.snapshots(),
                  builder: (context, snapshot) {
                    final email = snapshot.data?.data()?['email'];
                    return Text('Email (private, only you can read this): ${email ?? '-'}');
                  },
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(_status!, style: const TextStyle(color: Colors.green)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const Divider(height: 48),
                TournamentsPanel(uid: widget.user.uid),
                const SizedBox(height: 24),
                Text('uid: ${widget.user.uid}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
