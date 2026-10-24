import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'teams_section.dart';

// Debug-harness slice for tournaments: a form that calls createTournament, and a live list of
// the tournaments this user organizes. Reads are Firestore listeners; the only write path is the
// createTournament Cloud Function. The invite code lives in tournaments/{id}/private/settings
// (members and admins only), so it is read from that document, not the tournament itself.
class TournamentsPanel extends StatefulWidget {
  const TournamentsPanel({super.key, required this.uid});

  final String uid;

  @override
  State<TournamentsPanel> createState() => _TournamentsPanelState();
}

class _TournamentsPanelState extends State<TournamentsPanel> {
  final _name = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  bool _public = false;
  bool _creating = false;
  String? _status;
  String? _error;

  HttpsCallable get _create =>
      FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createTournament');

  // Every roster entry carries its player's uid, so "my tournaments" is one collection-group query
  // (the organizer is on their own roster too). Needs the collection-group index on playerId.
  Query<Map<String, dynamic>> get _memberships => FirebaseFirestore.instance
      .collectionGroup('players')
      .where('playerId', isEqualTo: widget.uid);

  final _code = TextEditingController();
  bool _joining = false;
  String? _joinStatus;
  String? _joinError;

  HttpsCallable get _join =>
      FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('joinTournament');

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _joinTournament() async {
    setState(() {
      _joining = true;
      _joinStatus = null;
      _joinError = null;
    });
    try {
      final result = await _join.call({'inviteCode': _code.text});
      final data = Map<String, dynamic>.from(result.data as Map);
      if (mounted) {
        setState(() {
          _joinStatus = data['alreadyMember'] == true
              ? 'You are already in "${data['name']}".'
              : 'Joined "${data['name']}".';
          _code.clear();
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _joinError = '${e.code}: ${e.message}');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _createTournament() async {
    setState(() {
      _creating = true;
      _status = null;
      _error = null;
    });
    try {
      final result = await _create.call({
        'name': _name.text,
        if (_start.text.trim().isNotEmpty) 'startDate': _start.text.trim(),
        if (_end.text.trim().isNotEmpty) 'endDate': _end.text.trim(),
        'visibility': _public ? 'public' : 'private',
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      if (mounted) {
        setState(() {
          _status =
              'Created "${data['name']}" - invite code ${data['inviteCode']}';
          _name.clear();
          _start.clear();
          _end.clear();
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = '${e.code}: ${e.message}');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Create a tournament', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Goes through the createTournament function. Dates are optional (YYYY-MM-DD).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Tournament name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _start,
                decoration: const InputDecoration(
                  labelText: 'Start date',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _end,
                decoration: const InputDecoration(
                  labelText: 'End date',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Public (anyone signed in can watch)'),
          value: _public,
          onChanged: (v) => setState(() => _public = v),
        ),
        FilledButton(
          onPressed: _creating ? null : _createTournament,
          child: const Text('Create tournament'),
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
        Text('Join a tournament', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Goes through the joinTournament function.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Invite code',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _joining ? null : _joinTournament(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _joining ? null : _joinTournament,
          child: const Text('Join tournament'),
        ),
        if (_joinStatus != null) ...[
          const SizedBox(height: 12),
          Text(_joinStatus!, style: const TextStyle(color: Colors.green)),
        ],
        if (_joinError != null) ...[
          const SizedBox(height: 12),
          Text(_joinError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        Text('Your tournaments', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Live from Firestore (every tournament you are on the roster of).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _memberships.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                '${snapshot.error}',
                style: TextStyle(color: theme.colorScheme.error),
              );
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return const Text('None yet.');
            return Column(
              children: [
                for (final entry in docs)
                  _TournamentTile(
                    key: ValueKey(entry.reference.path),
                    uid: widget.uid,
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

class _TournamentTile extends StatelessWidget {
  const _TournamentTile({
    super.key,
    required this.uid,
    required this.tournamentId,
  });

  final String uid;
  final String tournamentId;

  @override
  Widget build(BuildContext context) {
    final tournament = FirebaseFirestore.instance
        .collection('tournaments')
        .doc(tournamentId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tournament.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Rules refuse non-admins a suspended tournament, so this is what a member sees.
          return Card(
            child: ListTile(
              title: const Text('Tournament unavailable'),
              subtitle: Text(
                'It may be suspended. $tournamentId\n${snapshot.error}',
              ),
              isThreeLine: true,
            ),
          );
        }
        final data = snapshot.data?.data();
        if (data == null) return const SizedBox.shrink();
        final isOrganizer = data['organizerId'] == uid;
        final isAdmin = isOrganizer || data['coAdminId'] == uid;
        final role = isOrganizer
            ? 'organizer'
            : (isAdmin ? 'co-admin' : 'player');
        final dates = [
          data['startDate'],
          data['endDate'],
        ].whereType<String>().join(' to ');
        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                title: Text('${data['name']}'),
                subtitle: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: tournament
                      .collection('private')
                      .doc('settings')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final code = snapshot.data?.data()?['inviteCode'] ?? '-';
                    return Text(
                      'You: $role\n'
                      '${data['visibility']} - ${data['status']}'
                      '${dates.isEmpty ? '' : ' - $dates'}\n'
                      'Invite code: $code',
                    );
                  },
                ),
                isThreeLine: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TeamsSection(
                  tournamentId: tournamentId,
                  canEdit: isAdmin,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
