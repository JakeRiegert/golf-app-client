import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'dialog_utils.dart';
import 'rounds_section.dart' show playerNameOf;

// Tees and check-in for one round, shown on the round card. Everyone sees who has checked in and which tee each player
// plays; a player picks their own tee (men's or women's rating table) and checks in; an organizer or co-admin can set any
// player's tee ahead of time (setting a tee is not checking in), check people in, and set a tee for everyone at once.
// Reads come from Firestore (rounds/{id}/roundPlayers); every change goes through the setRoundPlayers function.

FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: 'us-central1');

class _Pick {
  const _Pick({this.teeId, this.table, required this.checkedIn});
  final String? teeId;
  final String? table;
  final bool checkedIn;
}

class CheckInPanel extends StatelessWidget {
  const CheckInPanel({
    super.key,
    required this.tournamentId,
    required this.roundId,
    required this.round,
    required this.uid,
    required this.canEdit,
  });

  final String tournamentId;
  final String roundId;
  final Map<String, dynamic> round;
  final String uid;
  final bool canEdit;

  DocumentReference<Map<String, dynamic>> get _tournament =>
      FirebaseFirestore.instance.collection('tournaments').doc(tournamentId);

  List<Map<String, dynamic>> get _tees {
    final course = round['course'];
    final tees = course is Map ? course['tees'] : null;
    if (tees is! List) return const [];
    return [for (final t in tees) Map<String, dynamic>.from(t as Map)];
  }

  String? get _defaultTeeId => round['defaultTeeId'] as String?;

  // "Blue · 6,120 yds" over the holes this round plays, or just the name when no yardage is entered.
  String _teeLabel(Map<String, dynamic> tee) {
    final first = (round['firstHole'] as num?)?.toInt() ?? 1;
    final count = (round['holesPlanned'] as num?)?.toInt() ?? 18;
    final yards = (tee['yards'] as List?) ?? const [];
    var total = 0;
    for (var i = first - 1; i < first - 1 + count && i < yards.length; i++) {
      total += (yards[i] as num?)?.toInt() ?? 0;
    }
    return total > 0 ? '${tee['name']} · $total yds' : '${tee['name']}';
  }

  String _teeName(String? teeId) {
    if (teeId == null) return 'no tee yet';
    for (final t in _tees) {
      if (t['id'] == teeId) return '${t['name']}';
    }
    return 'unknown tee';
  }

  String _statusLine(Map<String, dynamic>? pick) {
    final tee = pick?['teeId'] as String?;
    final table = pick?['table'] as String?;
    if (_tees.isEmpty) return pick?['checkedIn'] == true ? 'Checked in' : 'Not checked in';
    final plays = tee == null
        ? 'No tee chosen yet'
        : '${_teeName(tee)} tees${table == null ? '' : ", ${table == 'women' ? "women's" : "men's"} rating"}';
    return '${pick?['checkedIn'] == true ? 'Checked in' : 'Not checked in'} · $plays';
  }

  Future<void> _send(BuildContext context, List<Map<String, Object?>> players, String done) async {
    try {
      await _functions.httpsCallable('setRoundPlayers').call({
        'tournamentId': tournamentId,
        'roundId': roundId,
        'players': players,
      });
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(done), backgroundColor: Colors.green.shade700));
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) showErrorMessage(context, friendlyError(e));
    }
  }

  // Edit one player's tee, rating table and check-in. [self] is the signed-in player editing their own entry.
  Future<void> _editPlayer(BuildContext context, String playerId, String name, Map<String, dynamic>? pick, {required bool self}) async {
    final tees = _tees;
    if (tees.isEmpty) {
      // No tee sets on this course: checking in is the only thing to do.
      await _send(context, [
        {'playerId': playerId, 'checkedIn': pick?['checkedIn'] != true},
      ], pick?['checkedIn'] == true ? 'Check-in removed.' : 'Checked in.');
      return;
    }
    final result = await showDialog<_Pick>(
      context: context,
      builder: (_) => _TeeDialog(
        title: self ? 'Check in' : name,
        tees: tees,
        labelOf: _teeLabel,
        initialTeeId: (pick?['teeId'] as String?) ?? (self ? _defaultTeeId : null),
        initialTable: pick?['table'] as String?,
        initialCheckedIn: pick?['checkedIn'] == true,
        self: self,
      ),
    );
    if (result == null || !context.mounted) return;
    await _send(context, [
      {
        'playerId': playerId,
        'teeId': result.teeId,
        'table': result.table,
        'checkedIn': result.checkedIn,
      },
    ], result.checkedIn ? 'Checked in.' : 'Saved.');
  }

  Future<void> _setEveryone(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> roster, Map<String, Map<String, dynamic>> picks) async {
    final tees = _tees;
    final teeId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Everyone without a tee plays...'),
        children: [
          for (final t in tees)
            SimpleDialogOption(onPressed: () => popDialog(context, '${t['id']}'), child: Text(_teeLabel(t))),
          SimpleDialogOption(onPressed: () => popDialog(context), child: const Text('Cancel')),
        ],
      ),
    );
    if (teeId == null || !context.mounted) return;
    final ids = [
      for (final doc in roster)
        if (doc.data()['withdrawn'] != true && picks[doc.id]?['teeId'] == null) doc.id,
    ];
    if (ids.isEmpty) {
      showErrorMessage(context, 'Everyone already has a tee.');
      return;
    }
    for (var i = 0; i < ids.length; i += 100) {
      if (!context.mounted) return;
      await _send(context, [
        for (final id in ids.skip(i).take(100)) {'playerId': id, 'teeId': teeId},
      ], 'Tee set for ${ids.length} player${ids.length == 1 ? '' : 's'}. They are not checked in yet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picksStream = _tournament.collection('rounds').doc(roundId).collection('roundPlayers').snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: picksStream,
      builder: (context, picksSnap) {
        if (picksSnap.hasError) {
          return Text('${picksSnap.error}', style: TextStyle(color: theme.colorScheme.error));
        }
        final picks = {for (final d in picksSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) d.id: d.data()};
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _tournament.collection('players').snapshots(),
          builder: (context, rosterSnap) {
            final roster = [
              for (final d in rosterSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                if (d.data()['withdrawn'] != true) d,
            ];
            final checkedIn = roster.where((d) => picks[d.id]?['checkedIn'] == true).length;
            final mine = picks[uid];
            final onRoster = roster.any((d) => d.id == uid);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Check-in ($checkedIn of ${roster.length})',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (canEdit && _tees.isNotEmpty)
                      TextButton(
                        onPressed: () => _setEveryone(context, roster, picks),
                        child: const Text("Set everyone's tee"),
                      ),
                  ],
                ),
                if (onRoster)
                  Card(
                    color: theme.colorScheme.secondaryContainer,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: const Text('You'),
                      subtitle: Text(_statusLine(mine)),
                      trailing: FilledButton(
                        onPressed: () => _editPlayer(context, uid, 'You', mine, self: true),
                        child: Text(mine?['checkedIn'] == true ? 'Change' : 'Check in'),
                      ),
                    ),
                  ),
                if (_tees.isEmpty && canEdit)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'This round has no tees yet. Add them under Round settings > Course so players can pick one.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                for (final doc in roster)
                  if (doc.id != uid)
                    _PlayerLine(
                      playerId: doc.id,
                      pick: picks[doc.id],
                      status: _statusLine(picks[doc.id]),
                      onEdit: canEdit ? () => _editPlayer(context, doc.id, '', picks[doc.id], self: false) : null,
                    ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PlayerLine extends StatelessWidget {
  const _PlayerLine({required this.playerId, required this.pick, required this.status, required this.onEdit});

  final String playerId;
  final Map<String, dynamic>? pick;
  final String status;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final checked = pick?['checkedIn'] == true;
    return FutureBuilder<String>(
      future: playerNameOf(playerId),
      builder: (context, snap) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(checked ? Icons.check_circle : Icons.radio_button_unchecked, color: checked ? Colors.green.shade700 : null),
        title: Text(snap.data ?? '...'),
        subtitle: Text(status),
        trailing: onEdit == null ? null : IconButton(tooltip: 'Set tee or check in', icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
      ),
    );
  }
}

// Pick a tee and which rating table applies (men's or women's), then check in. An organizer editing someone else sees a
// "checked in" switch and can leave the tee empty.
class _TeeDialog extends StatefulWidget {
  const _TeeDialog({
    required this.title,
    required this.tees,
    required this.labelOf,
    required this.initialTeeId,
    required this.initialTable,
    required this.initialCheckedIn,
    required this.self,
  });

  final String title;
  final List<Map<String, dynamic>> tees;
  final String Function(Map<String, dynamic>) labelOf;
  final String? initialTeeId;
  final String? initialTable;
  final bool initialCheckedIn;
  final bool self;

  @override
  State<_TeeDialog> createState() => _TeeDialogState();
}

class _TeeDialogState extends State<_TeeDialog> {
  late String? _tee = widget.initialTeeId;
  late String? _table = widget.initialTable;
  late bool _checkedIn = widget.initialCheckedIn;

  Map<String, dynamic>? get _selected {
    for (final t in widget.tees) {
      if (t['id'] == _tee) return t;
    }
    return null;
  }

  // A tee that lists ratings for only one table cannot be played by the other.
  bool _allows(Map<String, dynamic> tee, String table) {
    final hasAny = tee['men'] != null || tee['women'] != null;
    return !hasAny || tee[table] != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    final menOk = selected == null || _allows(selected, 'men');
    final womenOk = selected == null || _allows(selected, 'women');
    final canCheckIn = _tee != null && _table != null;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tee', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in widget.tees)
                  ChoiceChip(
                    label: Text(widget.labelOf(t)),
                    selected: _tee == t['id'],
                    onSelected: (_) => setState(() {
                      _tee = '${t['id']}';
                      if (_table != null && !_allows(t, _table!)) _table = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text("Rating table", style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              emptySelectionAllowed: true,
              segments: [
                ButtonSegment(value: 'men', label: const Text("Men's"), enabled: menOk),
                ButtonSegment(value: 'women', label: const Text("Women's"), enabled: womenOk),
              ],
              selected: {?_table},
              onSelectionChanged: (s) => setState(() => _table = s.isEmpty ? null : s.first),
            ),
            const SizedBox(height: 4),
            Text(
              "Decides which course rating and slope the player's handicap is worked out from.",
              style: theme.textTheme.bodySmall,
            ),
            if (!widget.self)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Checked in'),
                subtitle: canCheckIn || !_checkedIn ? null : const Text('Needs a tee and a rating table.'),
                value: _checkedIn,
                onChanged: (v) => setState(() => _checkedIn = v),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.self && widget.initialCheckedIn)
          TextButton(
            onPressed: () => popDialog(context, _Pick(teeId: _tee, table: _table, checkedIn: false)),
            child: const Text('Undo check-in'),
          ),
        TextButton(onPressed: () => popDialog(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: widget.self
              ? (canCheckIn ? () => popDialog(context, _Pick(teeId: _tee, table: _table, checkedIn: true)) : null)
              : (_checkedIn && !canCheckIn ? null : () => popDialog(context, _Pick(teeId: _tee, table: _table, checkedIn: _checkedIn))),
          child: Text(widget.self ? (widget.initialCheckedIn ? 'Save' : 'Check in') : 'Save'),
        ),
      ],
    );
  }
}
