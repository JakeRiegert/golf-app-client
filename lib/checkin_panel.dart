import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'dialog_utils.dart';
import 'rounds_section.dart' show playerNameOf;

// Tees and check-in for one round. Check-in is only a way for the organizer to see who has turned up and which tee each
// player plays: it never holds up a round, scoring or a tournament. Everyone sees the count; a player picks their own
// tee (men's or women's rating table) and checks in; an organizer or co-admin can do all of that for anyone, ahead of
// time or afterwards (a player who hands in a card and leaves the rest to them), and sets tees for everyone at once.
// Setting a tee is not checking in. On the round card an organizer sees a compact block with a Manage button that opens
// the full check-in page (CheckInPage); players see the whole list on the card. A check-in an organizer did for a
// player is shown in a different colour from one the player did themselves.
// Reads come from Firestore (rounds/{id}/roundPlayers); every change goes through the setRoundPlayers function.

FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: 'us-central1');

class _Pick {
  const _Pick({this.teeId, this.table, required this.checkedIn});
  final String? teeId;
  final String? table;
  final bool checkedIn;
}

// Colours: green = the player checked in themselves, blue = an organizer did it for them.
Color _selfColor() => Colors.green.shade700;
Color _organizerColor() => Colors.blue.shade700;

// The organizer's full check-in page for one round: who is in, who is not, one tap to check someone in.
class CheckInPage extends StatelessWidget {
  const CheckInPage({super.key, required this.tournamentId, required this.roundId, required this.uid});

  final String tournamentId;
  final String roundId;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final roundRef = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('rounds').doc(roundId);
    return Scaffold(
      appBar: AppBar(title: const Text('Check-in')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: roundRef.snapshots(),
        builder: (context, snap) {
          final round = snap.data?.data();
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (round == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CheckInPanel(
                tournamentId: tournamentId,
                roundId: roundId,
                round: round,
                uid: uid,
                canEdit: true,
                fullPage: true,
              ),
            ],
          );
        },
      ),
    );
  }
}

class CheckInPanel extends StatelessWidget {
  const CheckInPanel({
    super.key,
    required this.tournamentId,
    required this.roundId,
    required this.round,
    required this.uid,
    required this.canEdit,
    this.fullPage = false,
  });

  final String tournamentId;
  final String roundId;
  final Map<String, dynamic> round;
  final String uid;
  final bool canEdit;
  final bool fullPage;

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

  // Checked in by someone other than the player: an organizer did it for them.
  static bool byOrganizer(String playerId, Map<String, dynamic>? pick) {
    final by = pick?['checkedInBy'] as String?;
    return pick?['checkedIn'] == true && by != null && by != playerId;
  }

  String _statusLine(String playerId, Map<String, dynamic>? pick) {
    final checked = pick?['checkedIn'] == true;
    final head = !checked ? 'Not checked in' : (byOrganizer(playerId, pick) ? 'Checked in by organizer' : 'Checked in');
    if (_tees.isEmpty) return head;
    final tee = pick?['teeId'] as String?;
    final table = pick?['table'] as String?;
    final plays = tee == null
        ? 'No tee chosen yet'
        : '${_teeName(tee)} tees${table == null ? '' : ", ${table == 'women' ? "women's" : "men's"} rating"}';
    // A tee an organizer set ahead of time, before the player has checked in.
    return '$head · ${!checked && tee != null ? 'Pre-set: $plays' : plays}';
  }

  Future<bool> _send(BuildContext context, List<Map<String, Object?>> players, String done) async {
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
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) showErrorMessage(context, friendlyError(e));
      return false;
    }
  }

  // Edit one player's tee, rating table and check-in. [self] is the signed-in player editing their own entry on the
  // round card; the organizer's page edits everyone, themselves included, with the "checked in" switch.
  Future<void> _editPlayer(BuildContext context, String playerId, Map<String, dynamic>? pick,
      {required bool self, bool startCheckedIn = false}) async {
    final tees = _tees;
    if (tees.isEmpty) {
      // No tee sets on this course: checking in is the only thing to do.
      await _send(context, [
        {'playerId': playerId, 'checkedIn': pick?['checkedIn'] != true},
      ], pick?['checkedIn'] == true ? 'Check-in removed.' : 'Checked in.');
      return;
    }
    final name = self ? 'Check in' : await playerNameOf(playerId);
    if (!context.mounted) return;
    final result = await showDialog<_Pick>(
      context: context,
      builder: (_) => _TeeDialog(
        title: name,
        tees: tees,
        labelOf: _teeLabel,
        initialTeeId: (pick?['teeId'] as String?) ?? (self || startCheckedIn ? _defaultTeeId : null),
        initialTable: pick?['table'] as String?,
        initialCheckedIn: pick?['checkedIn'] == true || startCheckedIn,
        wasCheckedIn: pick?['checkedIn'] == true,
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

  // One tap for the organizer: check the player in with what is already set. Needs the rating table (a visible choice),
  // so with none set the dialog opens instead, ready to check in.
  Future<void> _quickCheckIn(BuildContext context, String playerId, Map<String, dynamic>? pick) async {
    if (_tees.isEmpty || pick?['table'] != null) {
      await _send(context, [
        {'playerId': playerId, 'checkedIn': true},
      ], 'Checked in.');
      return;
    }
    await _editPlayer(context, playerId, pick, self: false, startCheckedIn: true);
  }

  Future<void> _undo(BuildContext context, String playerId) async {
    await _send(context, [
      {'playerId': playerId, 'checkedIn': false},
    ], 'Check-in removed.');
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

  PlayerLine _line(BuildContext context, String playerId, Map<String, dynamic>? pick, {required bool manage}) {
    return PlayerLine(
      playerId: playerId,
      checked: pick?['checkedIn'] == true,
      byOrganizer: byOrganizer(playerId, pick),
      status: _statusLine(playerId, pick),
      onCheckIn: manage && canEdit && pick?['checkedIn'] != true ? () => _quickCheckIn(context, playerId, pick) : null,
      onUndo: manage && canEdit && pick?['checkedIn'] == true ? () => _undo(context, playerId) : null,
      onEdit: canEdit ? () => _editPlayer(context, playerId, pick, self: false) : null,
    );
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
            final waiting = [for (final d in roster) if (picks[d.id]?['checkedIn'] != true) d];
            final done = [for (final d in roster) if (picks[d.id]?['checkedIn'] == true) d];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fullPage ? '$checkedIn of ${roster.length} checked in' : 'Check-in ($checkedIn of ${roster.length})',
                        style: fullPage ? theme.textTheme.titleMedium : theme.textTheme.titleSmall,
                      ),
                    ),
                    if (canEdit && !fullPage)
                      TextButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => CheckInPage(tournamentId: tournamentId, roundId: roundId, uid: uid),
                          ),
                        ),
                        child: const Text('Manage'),
                      ),
                    if (canEdit && fullPage && _tees.isNotEmpty)
                      TextButton(
                        onPressed: () => _setEveryone(context, roster, picks),
                        child: const Text("Set everyone's tee"),
                      ),
                  ],
                ),
                if (fullPage) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'This is only so you can see what is going on. Nobody is ever held up for not being checked in, '
                      'and scores count either way.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Wrap(
                    spacing: 16,
                    children: [
                      _LegendDot(icon: Icons.check_circle, color: _selfColor(), label: 'Checked in themselves'),
                      _LegendDot(icon: Icons.how_to_reg, color: _organizerColor(), label: 'Checked in by organizer'),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (!fullPage && onRoster)
                  Card(
                    color: theme.colorScheme.secondaryContainer,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: const Text('You'),
                      subtitle: Text(_statusLine(uid, mine)),
                      trailing: FilledButton(
                        onPressed: () => _editPlayer(context, uid, mine, self: true),
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
                if (fullPage) ...[
                  if (waiting.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Not checked in (${waiting.length})', style: theme.textTheme.titleSmall),
                    ),
                    for (final doc in waiting) _line(context, doc.id, picks[doc.id], manage: true),
                  ],
                  if (done.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text('Checked in (${done.length})', style: theme.textTheme.titleSmall),
                    ),
                    for (final doc in done) _line(context, doc.id, picks[doc.id], manage: true),
                  ],
                ] else if (!canEdit) ...[
                  for (final doc in roster)
                    if (doc.id != uid) _line(context, doc.id, picks[doc.id], manage: false),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// One player's line. Visible only for display and for the organizer's one-tap actions; players never get buttons here.
class PlayerLine extends StatelessWidget {
  const PlayerLine({
    super.key,
    required this.playerId,
    required this.checked,
    required this.byOrganizer,
    required this.status,
    this.onCheckIn,
    this.onUndo,
    this.onEdit,
  });

  final String playerId;
  final bool checked;
  final bool byOrganizer;
  final String status;
  final VoidCallback? onCheckIn;
  final VoidCallback? onUndo;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final Widget icon = !checked
        ? const Icon(Icons.radio_button_unchecked)
        : byOrganizer
            ? Icon(Icons.how_to_reg, color: _organizerColor())
            : Icon(Icons.check_circle, color: _selfColor());
    return FutureBuilder<String>(
      future: playerNameOf(playerId),
      builder: (context, snap) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: icon,
        title: Text(snap.data ?? '...'),
        subtitle: Text(status),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onCheckIn != null) FilledButton.tonal(onPressed: onCheckIn, child: const Text('Check in')),
            if (onUndo != null) TextButton(onPressed: onUndo, child: const Text('Undo')),
            if (onEdit != null) IconButton(tooltip: 'Set tee or check in', icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
          ],
        ),
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
    required this.wasCheckedIn,
    required this.self,
  });

  final String title;
  final List<Map<String, dynamic>> tees;
  final String Function(Map<String, dynamic>) labelOf;
  final String? initialTeeId;
  final String? initialTable;
  final bool initialCheckedIn;
  final bool wasCheckedIn;
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
        if (widget.self && widget.wasCheckedIn)
          TextButton(
            onPressed: () => popDialog(context, _Pick(teeId: _tee, table: _table, checkedIn: false)),
            child: const Text('Undo check-in'),
          ),
        TextButton(onPressed: () => popDialog(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: widget.self
              ? (canCheckIn ? () => popDialog(context, _Pick(teeId: _tee, table: _table, checkedIn: true)) : null)
              : (_checkedIn && !canCheckIn ? null : () => popDialog(context, _Pick(teeId: _tee, table: _table, checkedIn: _checkedIn))),
          child: Text(widget.self ? (widget.wasCheckedIn ? 'Save' : 'Check in') : 'Save'),
        ),
      ],
    );
  }
}
