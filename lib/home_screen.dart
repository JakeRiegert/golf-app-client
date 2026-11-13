import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'dialog_utils.dart';
import 'tournaments_panel.dart';

// Signed-in home, in two pages (bottom tabs): the tournaments you are on the roster of, and your
// profile. Each tournament then opens its own pages (Overview, Teams, Players, Rounds).
//
// On arrival this calls the upsertPlayerProfile Cloud Function once (creating or touching this user's
// profile). The profile is shown live from Firestore and the display name is edited through the same
// function. Reads come straight from Firestore (live listeners); every write goes through a function,
// never directly from the client.
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
  int _tab = 0;

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
      if (mounted) setState(() => _error = friendlyError(e));
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
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatTime(Object? value) {
    if (value is Timestamp) return value.toDate().toLocal().toString();
    return '-';
  }

  // A readable width on a laptop; on a phone the page simply fills the screen.
  Widget _page(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  Widget _profile(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your profile', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Live from Firestore. Edits go through the upsertPlayerProfile function.',
          style: theme.textTheme.bodySmall,
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
                  style: theme.textTheme.bodySmall,
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
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => FirebaseAuth.instance.signOut(),
          child: const Text('Sign out'),
        ),
        const SizedBox(height: 16),
        Text('uid: ${widget.user.uid}', style: theme.textTheme.bodySmall),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tab == 0 ? 'Tournaments' : 'Profile')),
      body: _tab == 0 ? _page(TournamentsPanel(uid: widget.user.uid)) : _page(_profile(context)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Tournaments',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
