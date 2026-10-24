import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

// Debug-harness slice for the roster inside one tournament. Everyone on the roster is listed live
// from Firestore with their team and handicap. Two ways to put a player on a team, one record:
//   - a player can pick or change their own team (chooseTeam) until an admin has assigned them;
//   - the organizer or co-admin can assign anyone's team and handicap at any time
//     (assignTournamentPlayer). An admin assignment locks the player's own choice, and choosing
//     "No team" as admin hands control back.
// Handicap is admin-only. The functions enforce all of this; the UI just hides what you can't do.
class PlayersSection extends StatefulWidget {
  const PlayersSection({
    super.key,
    required this.tournamentId,
    required this.uid,
    required this.canEdit,
  });

  final String tournamentId;
  final String uid;
  final bool canEdit;

  @override
  State<PlayersSection> createState() => _PlayersSectionState();
}

class _PlayersSectionState extends State<PlayersSection> {
  bool _busy = false;
  String? _error;

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  DocumentReference<Map<String, dynamic>> get _tournament => FirebaseFirestore
      .instance
      .collection('tournaments')
      .doc(widget.tournamentId);

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

  Future<void> _assign(String playerId, Map<String, Object?> change) =>
      _run(() async {
        await _functions.httpsCallable('assignTournamentPlayer').call({
          'tournamentId': widget.tournamentId,
          'playerId': playerId,
          ...change,
        });
      });

  Future<void> _chooseOwnTeam(String? teamId) => _run(() async {
    await _functions.httpsCallable('chooseTeam').call({
      'tournamentId': widget.tournamentId,
      'teamId': teamId,
    });
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Players', style: theme.textTheme.titleSmall),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _tournament
              .collection('teams')
              .orderBy('createdAt')
              .snapshots(),
          builder: (context, teamSnap) {
            final teams = <String, String>{
              for (final doc in teamSnap.data?.docs ?? const [])
                doc.id: '${doc.data()['name']}',
            };
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _tournament.collection('players').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    '${snapshot.error}',
                    style: TextStyle(color: theme.colorScheme.error),
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) return const Text('No players yet.');
                return Column(
                  children: [
                    for (final doc in docs)
                      _PlayerRow(
                        key: ValueKey(doc.id),
                        playerId: doc.id,
                        data: doc.data(),
                        teams: teams,
                        isMe: doc.id == widget.uid,
                        canEdit: widget.canEdit,
                        busy: _busy,
                        onAdminTeam: (teamId) =>
                            _assign(doc.id, {'teamId': teamId}),
                        onAdminHandicap: (handicap) =>
                            _assign(doc.id, {'handicap': handicap}),
                        onOwnTeam: _chooseOwnTeam,
                      ),
                  ],
                );
              },
            );
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

class _PlayerRow extends StatefulWidget {
  const _PlayerRow({
    super.key,
    required this.playerId,
    required this.data,
    required this.teams,
    required this.isMe,
    required this.canEdit,
    required this.busy,
    required this.onAdminTeam,
    required this.onAdminHandicap,
    required this.onOwnTeam,
  });

  final String playerId;
  final Map<String, dynamic> data;
  final Map<String, String> teams;
  final bool isMe;
  final bool canEdit;
  final bool busy;
  final void Function(String? teamId) onAdminTeam;
  final void Function(num? handicap) onAdminHandicap;
  final void Function(String? teamId) onOwnTeam;

  @override
  State<_PlayerRow> createState() => _PlayerRowState();
}

class _PlayerRowState extends State<_PlayerRow> {
  late final TextEditingController _handicap = TextEditingController(
    text: _handicapText(widget.data['handicap']),
  );

  static String _handicapText(Object? value) => value is num ? '$value' : '';

  @override
  void didUpdateWidget(_PlayerRow old) {
    super.didUpdateWidget(old);
    if (old.data['handicap'] != widget.data['handicap']) {
      _handicap.text = _handicapText(widget.data['handicap']);
    }
  }

  @override
  void dispose() {
    _handicap.dispose();
    super.dispose();
  }

  void _saveHandicap() {
    final text = _handicap.text.trim();
    widget.onAdminHandicap(text.isEmpty ? null : num.tryParse(text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teamId = widget.data['teamId'] as String?;
    final assignedBy = widget.data['teamAssignedBy'] as String?;
    final lockedByAdmin = assignedBy == 'admin';
    final canPick = widget.canEdit || (widget.isMe && !lockedByAdmin);
    // A team the roster entry points at that no longer exists shows as "No team".
    final selected = widget.teams.containsKey(teamId) ? teamId : null;

    final handicap = widget.data['handicap'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('players')
                .doc(widget.playerId)
                .snapshots(),
            builder: (context, snapshot) {
              final name = snapshot.data?.data()?['displayName'] as String?;
              final label = name ?? 'Player ${widget.playerId.substring(0, 6)}';
              return Text(
                widget.isMe ? '$label (you)' : label,
                style: theme.textTheme.bodyMedium,
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String?>(
                  initialValue: selected,
                  key: ValueKey('team-${widget.playerId}-$selected'),
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Team',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No team'),
                    ),
                    for (final entry in widget.teams.entries)
                      DropdownMenuItem<String?>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: canPick && !widget.busy
                      ? (value) => widget.canEdit
                            ? widget.onAdminTeam(value)
                            : widget.onOwnTeam(value)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: widget.canEdit
                    ? TextField(
                        controller: _handicap,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Handicap',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.check, size: 18),
                            tooltip: 'Save handicap',
                            onPressed: widget.busy ? null : _saveHandicap,
                          ),
                        ),
                        onSubmitted: (_) =>
                            widget.busy ? null : _saveHandicap(),
                      )
                    : Text('HCP ${handicap is num ? handicap : '-'}'),
              ),
            ],
          ),
          if (teamId != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                lockedByAdmin
                    ? 'Team set by the organizer'
                    : 'Team chosen by the player',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
