import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'dialog_utils.dart';
import 'input_parsing.dart';

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
    required this.started,
    required this.organizerId,
    required this.coAdminId,
  });

  final String tournamentId;
  final String uid;
  final bool canEdit;
  final String? organizerId;
  final String? coAdminId;

  // Once an admin has started the tournament, players can no longer change their own handicap.
  final bool started;

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
      if (mounted) {
        setState(() => _error = friendlyError(e));
        showErrorMessage(context, friendlyError(e));
      }
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

  // Admins only: name (or, with null, remove) the co-admin who shares the organizer's powers.
  Future<void> _setCoAdmin(String? playerId) => _run(() async {
    await _functions.httpsCallable('assignCoAdmin').call({
      'tournamentId': widget.tournamentId,
      'playerId': playerId,
    });
  });

  // Admins only: take a player off the roster. Before the start they are deleted (and can rejoin with
  // the invite code); after it they stay in the record as withdrawn and can no longer make changes.
  Future<void> _removePlayer(String playerId, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $label?'),
        content: Text(
          widget.started
              ? 'The tournament has started, so $label stays in the record as '
                    'withdrawn and can no longer make changes. Everyone is told.'
              : '$label comes off the roster and their team and handicap are '
                    'dropped. They can rejoin with the invite code.',
        ),
        actions: [
          TextButton(
            onPressed: () => popDialog(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => popDialog(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _functions.httpsCallable('removePlayer').call({
        'tournamentId': widget.tournamentId,
        'playerId': playerId,
      });
    });
  }

  Future<void> _setOwnHandicap(num? handicap) => _run(() async {
    await _functions.httpsCallable('setMyHandicap').call({
      'tournamentId': widget.tournamentId,
      'handicap': handicap,
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
                        started: widget.started,
                        isOrganizer: doc.id == widget.organizerId,
                        isCoAdmin: doc.id == widget.coAdminId,
                        onCoAdmin: (make) => _setCoAdmin(make ? doc.id : null),
                        onRemove: (label) => _removePlayer(doc.id, label),
                        busy: _busy,
                        onAdminTeam: (teamId) =>
                            _assign(doc.id, {'teamId': teamId}),
                        onAdminHandicap: (handicap) =>
                            _assign(doc.id, {'handicap': handicap}),
                        onOwnTeam: _chooseOwnTeam,
                        onOwnHandicap: _setOwnHandicap,
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
    required this.started,
    required this.isOrganizer,
    required this.isCoAdmin,
    required this.onCoAdmin,
    required this.onRemove,
    required this.busy,
    required this.onAdminTeam,
    required this.onAdminHandicap,
    required this.onOwnTeam,
    required this.onOwnHandicap,
  });

  final String playerId;
  final Map<String, dynamic> data;
  final Map<String, String> teams;
  final bool isMe;
  final bool canEdit;
  final bool started;
  final bool isOrganizer;
  final bool isCoAdmin;
  final void Function(bool make) onCoAdmin;
  final void Function(String label) onRemove;
  final bool busy;
  final void Function(String? teamId) onAdminTeam;
  final void Function(num? handicap) onAdminHandicap;
  final void Function(String? teamId) onOwnTeam;
  final void Function(num? handicap) onOwnHandicap;

  @override
  State<_PlayerRow> createState() => _PlayerRowState();
}

class _PlayerRowState extends State<_PlayerRow> {
  late final TextEditingController _handicap = TextEditingController(
    text: _handicapText(widget.data['handicap']),
  );

  String? _handicapError;

  static String _handicapText(Object? value) => value is num ? '$value' : '';

  @override
  void didUpdateWidget(_PlayerRow old) {
    super.didUpdateWidget(old);
    if (old.data['handicap'] != widget.data['handicap']) {
      _handicap.text = _handicapText(widget.data['handicap']);
      _handicapError = null;
    }
  }

  @override
  void dispose() {
    _handicap.dispose();
    super.dispose();
  }

  void _saveHandicap() {
    // An empty box clears the handicap; text that is not a number in range is an error to show,
    // not a silent clear.
    final parsed = parseHandicap(_handicap.text);
    if (!parsed.ok) {
      setState(() => _handicapError = parsed.error);
      return;
    }
    setState(() => _handicapError = null);
    final value = parsed.value;
    if (widget.canEdit) {
      widget.onAdminHandicap(value);
    } else {
      widget.onOwnHandicap(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teamId = widget.data['teamId'] as String?;
    final assignedBy = widget.data['teamAssignedBy'] as String?;
    final lockedByAdmin = assignedBy == 'admin';
    // A withdrawn player was removed after the start: their entry is kept for the record, but
    // nothing about it can be changed from here.
    final withdrawn = widget.data['withdrawn'] == true;
    // Players pick their own team only before the start, and never once an admin has set it.
    final canPick =
        !withdrawn &&
        (widget.canEdit || (widget.isMe && !lockedByAdmin && !widget.started));
    // A team the roster entry points at that no longer exists shows as "No team".
    final selected = widget.teams.containsKey(teamId) ? teamId : null;

    final handicap = widget.data['handicap'];
    // Admins can always change a handicap; a player only their own, and only before the start.
    final canEditHandicap =
        !withdrawn && (widget.canEdit || (widget.isMe && !widget.started));
    final handicapSetBy = widget.data['handicapSetBy'] as String?;
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
              final role = widget.isOrganizer
                  ? ' - organizer'
                  : (widget.isCoAdmin ? ' - co-admin' : '');
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.isMe ? '$label (you)' : label}$role'
                      '${withdrawn ? ' - withdrawn' : ''}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        decoration: withdrawn
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  // Admins can name or remove the co-admin; the organizer is already an admin.
                  if (widget.canEdit && !widget.isOrganizer && !withdrawn)
                    TextButton(
                      onPressed: widget.busy
                          ? null
                          : () => widget.onCoAdmin(!widget.isCoAdmin),
                      child: Text(
                        widget.isCoAdmin ? 'Remove co-admin' : 'Make co-admin',
                      ),
                    ),
                  // Admins can take anyone but the organizer, and themselves, off the roster.
                  if (widget.canEdit &&
                      !widget.isOrganizer &&
                      !widget.isMe &&
                      !withdrawn)
                    TextButton(
                      onPressed: widget.busy
                          ? null
                          : () => widget.onRemove(label),
                      child: const Text('Remove'),
                    ),
                ],
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
                child: canEditHandicap
                    ? TextField(
                        controller: _handicap,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        onChanged: (_) {
                          if (_handicapError != null) {
                            setState(() => _handicapError = null);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Handicap',
                          errorText: _handicapError,
                          errorMaxLines: 3,
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
                    : Text(
                        'HCP ${handicap is num ? handicap : '-'}'
                        '${widget.isMe && widget.started ? ' (locked)' : ''}',
                      ),
              ),
            ],
          ),
          if (teamId != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                lockedByAdmin
                    ? 'Team set by the organizer'
                    : (widget.isMe && widget.started && !widget.canEdit
                          ? 'Team chosen by the player (locked: tournament started)'
                          : 'Team chosen by the player'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (handicap is num && handicapSetBy != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                handicapSetBy == 'admin'
                    ? 'Handicap set by the organizer'
                    : 'Handicap entered by the player',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
