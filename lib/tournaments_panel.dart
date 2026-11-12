import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'create_tournament_page.dart';
import 'dialog_utils.dart';
import 'tournament_screen.dart';

// The Tournaments tab: two buttons (new tournament, join with a code) and a live list of every
// tournament this user is on the roster of. Tap one to open it. Reads are Firestore listeners; creating
// and joining go through the createTournament and joinTournament functions.
class TournamentsPanel extends StatelessWidget {
  const TournamentsPanel({super.key, required this.uid});

  final String uid;

  // Every roster entry carries its player's uid, so "my tournaments" is one collection-group query
  // (the organizer is on their own roster too). Needs the collection-group index on playerId.
  Query<Map<String, dynamic>> get _memberships =>
      FirebaseFirestore.instance.collectionGroup('players').where('playerId', isEqualTo: uid);

  Future<void> _create(BuildContext context) async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const CreateTournamentPage()),
    );
    if (created == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Created "${created['name']}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share this invite code so people can join:'),
            const SizedBox(height: 8),
            SelectableText('${created['inviteCode']}', style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: '${created['inviteCode']}')),
            child: const Text('Copy code'),
          ),
          TextButton(onPressed: () => popDialog(context), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              popDialog(context);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TournamentScreen(tournamentId: created['id'] as String, uid: uid)),
              );
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Future<void> _join(BuildContext context) async {
    final code = await showDialog<String>(context: context, builder: (_) => const _JoinDialog());
    if (code == null || !context.mounted) return;
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('joinTournament').call({'inviteCode': code});
      final data = Map<String, dynamic>.from(result.data as Map);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(data['alreadyMember'] == true ? 'You are already in "${data['name']}".' : 'Joined "${data['name']}".'),
            backgroundColor: Colors.green.shade700,
          ),
        );
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) showErrorMessage(context, e.message ?? e.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _create(context),
                icon: const Icon(Icons.add),
                label: const Text('Create'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _join(context),
                icon: const Icon(Icons.login),
                label: const Text('Join'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Your tournaments', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _memberships.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('${snapshot.error}', style: TextStyle(color: theme.colorScheme.error));
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('None yet. Create one, or join with an invite code.'),
              );
            }
            return Column(
              children: [
                for (final entry in docs)
                  _TournamentTile(
                    key: ValueKey(entry.reference.path),
                    uid: uid,
                    tournamentId: entry.reference.parent.parent!.id,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join a tournament'),
      content: TextField(
        controller: _code,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Invite code', border: OutlineInputBorder()),
        onSubmitted: (_) => popDialog(context, _code.text),
      ),
      actions: [
        TextButton(onPressed: () => popDialog(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => popDialog(context, _code.text), child: const Text('Join')),
      ],
    );
  }
}

// One compact row per tournament; tapping opens its pages.
class _TournamentTile extends StatelessWidget {
  const _TournamentTile({super.key, required this.uid, required this.tournamentId});

  final String uid;
  final String tournamentId;

  @override
  Widget build(BuildContext context) {
    final tournament = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tournament.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Rules refuse non-admins a suspended tournament, so this is what a member sees.
          return Card(
            child: ListTile(
              title: const Text('Tournament unavailable'),
              subtitle: const Text('It may be suspended.'),
            ),
          );
        }
        final data = snapshot.data?.data();
        if (data == null) return const SizedBox.shrink();
        final isOrganizer = data['organizerId'] == uid;
        final isAdmin = isOrganizer || data['coAdminId'] == uid;
        final role = isOrganizer ? 'organizer' : (isAdmin ? 'co-admin' : 'player');
        final dates = [data['startDate'], data['endDate']].whereType<String>().join(' to ');
        final started = data['startedAt'] != null;
        return Card(
          child: ListTile(
            title: Text('${data['name']}'),
            subtitle: Text(
              '$role · ${started ? 'started' : 'not started'} · ${data['visibility']}'
              '${dates.isEmpty ? '' : '\n$dates'}',
            ),
            isThreeLine: dates.isNotEmpty,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TournamentScreen(tournamentId: tournamentId, uid: uid)),
            ),
          ),
        );
      },
    );
  }
}
