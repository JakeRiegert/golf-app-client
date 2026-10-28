import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'date_field.dart';
import 'players_section.dart';
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
          'Goes through the createTournament function. Dates are optional.',
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
              child: DateField(
                controller: _start,
                label: 'Start date',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DateField(
                controller: _end,
                label: 'End date',
                notBefore: _start,
                border: const OutlineInputBorder(),
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
        final started = data['startedAt'] != null;
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
                      ' - ${started ? 'started' : 'not started'}'
                      '${dates.isEmpty ? '' : ' - $dates'}'
                      '${data['wagerPotAmount'] is num ? ' - pot \$${data['wagerPotAmount']}' : ''}\n'
                      'Invite code: $code',
                    );
                  },
                ),
                isThreeLine: true,
              ),
              if (isAdmin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _AdminActions(
                    tournamentId: tournamentId,
                    data: data,
                    started: started,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TeamsSection(
                  tournamentId: tournamentId,
                  canEdit: isAdmin,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: PlayersSection(
                  tournamentId: tournamentId,
                  uid: uid,
                  canEdit: isAdmin,
                  started: started,
                  organizerId: data['organizerId'] as String?,
                  coAdminId: data['coAdminId'] as String?,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Admin-only actions on a tournament card: Edit (updateTournament), Start (startTournament) and
// Reopen (updateTournament with started: false). Start and Reopen ask first, since they change
// whether players can edit their own handicap.
class _AdminActions extends StatefulWidget {
  const _AdminActions({
    required this.tournamentId,
    required this.data,
    required this.started,
  });

  final String tournamentId;
  final Map<String, dynamic> data;
  final bool started;

  @override
  State<_AdminActions> createState() => _AdminActionsState();
}

class _AdminActionsState extends State<_AdminActions> {
  bool _busy = false;
  String? _error;

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = '${e.code}: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _start() async {
    final ok = await _confirm(
      'Start the tournament?',
      'Players will no longer be able to change their own handicap. '
          'You and any co-admin still can.',
      'Start',
    );
    if (!ok) return;
    await _run(() async {
      await _functions.httpsCallable('startTournament').call({
        'tournamentId': widget.tournamentId,
      });
    });
  }

  Future<void> _reopen() async {
    final ok = await _confirm(
      'Reopen the tournament?',
      'Players will be able to change their own handicap again until you '
          'start it.',
      'Reopen',
    );
    if (!ok) return;
    await _run(() async {
      await _functions.httpsCallable('updateTournament').call({
        'tournamentId': widget.tournamentId,
        'started': false,
      });
    });
  }

  Future<void> _edit() async {
    final changes = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _EditDialog(data: widget.data),
    );
    if (changes == null) return;
    await _run(() async {
      await _functions.httpsCallable('updateTournament').call({
        'tournamentId': widget.tournamentId,
        ...changes,
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : _edit,
              child: const Text('Edit'),
            ),
            widget.started
                ? OutlinedButton(
                    onPressed: _busy ? null : _reopen,
                    child: const Text('Reopen'),
                  )
                : FilledButton(
                    onPressed: _busy ? null : _start,
                    child: const Text('Start'),
                  ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

// Owns its text controllers so they are disposed only after the dialog has animated out.
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.data});

  final Map<String, dynamic> data;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _name = TextEditingController(text: '${widget.data['name']}');
  late final _start = TextEditingController(
    text: (widget.data['startDate'] as String?) ?? '',
  );
  late final _end = TextEditingController(
    text: (widget.data['endDate'] as String?) ?? '',
  );
  late final _pot = TextEditingController(
    text: widget.data['wagerPotAmount'] is num
        ? '${widget.data['wagerPotAmount']}'
        : '',
  );
  late bool _public = widget.data['visibility'] == 'public';

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    _pot.dispose();
    super.dispose();
  }

  void _save() {
    String? orNull(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final pot = orNull(_pot);
    Navigator.pop(context, <String, Object?>{
      'name': _name.text,
      'startDate': orNull(_start),
      'endDate': orNull(_end),
      'wagerPotAmount': pot == null ? null : num.tryParse(pot),
      'visibility': _public ? 'public' : 'private',
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit tournament'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              DateField(controller: _start, label: 'Start date'),
              DateField(controller: _end, label: 'End date', notBefore: _start),
              TextField(
                controller: _pot,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Team wager pot (optional)',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Public (anyone signed in can watch)'),
                value: _public,
                onChanged: (v) => setState(() => _public = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
