import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'dialog_utils.dart';
import 'rounds_section.dart' show playerNameOf;
import 'scoring_helpers.dart';

// The Score page of a tournament (debug harness, throwaway UI): pick a round and a group, step through the
// holes, save each player's score or a pickup, and watch the live scoreboard. A save is a small write to the
// round's score inbox (see firestore.rules); the server checks it and writes the official score, or turns it
// away with a reason that is shown next to the player. Nothing here decides a score: the screen only reads.

class ScoreSection extends StatefulWidget {
  const ScoreSection({super.key, required this.tournamentId, required this.uid, required this.isAdmin});

  final String tournamentId;
  final String uid;
  final bool isAdmin;

  @override
  State<ScoreSection> createState() => _ScoreSectionState();
}

class _ScoreSectionState extends State<ScoreSection> {
  String? _roundId;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _rounds =
      FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).collection('rounds').snapshots();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _rounds,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text('${snapshot.error}', style: TextStyle(color: theme.colorScheme.error));
        final all = [...(snapshot.data?.docs ?? [])]..sort((a, b) {
            final byDate = '${a.data()['date']}'.compareTo('${b.data()['date']}');
            if (byDate != 0) return byDate;
            return ((a.data()['number'] as num?) ?? 0).compareTo((b.data()['number'] as num?) ?? 0);
          });
        final docs = [for (final d in all) if (d.data()['status'] != 'cancelled') d];
        if (docs.isEmpty) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No rounds yet. Add one on the Rounds tab.'));
        }
        // Default to the round being played, else the first one still to play.
        final selected = docs.where((d) => d.id == _roundId).firstOrNull ??
            docs.where((d) => d.data()['status'] == 'live').firstOrNull ??
            docs.where((d) => d.data()['status'] == 'scheduled').firstOrNull ??
            docs.first;
        String label(QueryDocumentSnapshot<Map<String, dynamic>> d) {
          final name = d.data()['name'];
          final title = name is String && name.isNotEmpty ? name : 'Round ${docs.indexOf(d) + 1}';
          return '$title · ${d.data()['date']} · ${d.data()['status']}';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Score', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (docs.length > 1)
              DropdownButtonFormField<String>(
                initialValue: selected.id,
                decoration: const InputDecoration(labelText: 'Round'),
                items: [for (final d in docs) DropdownMenuItem(value: d.id, child: Text(label(d), overflow: TextOverflow.ellipsis))],
                onChanged: (id) => setState(() => _roundId = id),
              )
            else
              Text(label(selected), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _RoundScoring(
              key: ValueKey(selected.id),
              tournamentId: widget.tournamentId,
              roundId: selected.id,
              round: selected.data(),
              uid: widget.uid,
              isAdmin: widget.isAdmin,
            ),
          ],
        );
      },
    );
  }
}

class _RoundScoring extends StatefulWidget {
  const _RoundScoring({
    super.key,
    required this.tournamentId,
    required this.roundId,
    required this.round,
    required this.uid,
    required this.isAdmin,
  });

  final String tournamentId;
  final String roundId;
  final Map<String, dynamic> round;
  final String uid;
  final bool isAdmin;

  @override
  State<_RoundScoring> createState() => _RoundScoringState();
}

class _RoundScoringState extends State<_RoundScoring> {
  late final DocumentReference<Map<String, dynamic>> _round =
      FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).collection('rounds').doc(widget.roundId);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _groups = _round.collection('groups').orderBy('order').snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _scores = _round.collection('scores').snapshots();
  // Only my own submissions can be read (the rule), which is all this screen needs: the status of what I sent.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _mine = _round
      .collection('submissions')
      .where('enteredBy', isEqualTo: widget.uid)
      .snapshots(includeMetadataChanges: true);

  String? _groupId;
  int? _hole;
  final Map<String, int> _draft = {}; // '$playerId|$hole' -> the number being stepped to, before Save

  // Each player's tee pick for this round (rounds/{id}/roundPlayers), for the yardage shown on their card.
  Map<String, Map<String, dynamic>> _picks = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _picksSub;

  @override
  void initState() {
    super.initState();
    _picksSub = _round.collection('roundPlayers').snapshots().listen(
      (snap) {
        if (mounted) setState(() => _picks = {for (final d in snap.docs) d.id: d.data()});
      },
      // The yardage line is a nicety: if the picks cannot be read, the card simply shows no tee.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _picksSub?.cancel();
    super.dispose();
  }

  // "Blue tees · 168 yds" for this player on this hole, or null when the course has no tees. A player who has not picked
  // plays the round's default tee until they do.
  String? _teeNote(String playerId, int hole) {
    final tees = (widget.round['course'] as Map?)?['tees'];
    if (tees is! List || tees.isEmpty) return null;
    final teeId = (_picks[playerId]?['teeId'] as String?) ?? (widget.round['defaultTeeId'] as String?);
    final tee = tees.cast<Map>().where((t) => t['id'] == teeId).firstOrNull;
    if (tee == null) return null;
    final yards = (tee['yards'] as List?)?.elementAtOrNull(hole - 1) as num?;
    return '${tee['name']} tees${yards == null ? '' : ' · ${yards.toInt()} yds'}';
  }

  // The round's own data, read from the document that was handed in (it updates with the round stream above).
  int get _firstHole => (widget.round['firstHole'] as num?)?.toInt() ?? 1;
  int get _holesPlanned => (widget.round['holesPlanned'] as num?)?.toInt() ?? 18;
  List<int> get _skipped => [for (final h in (widget.round['skippedHoles'] as List?) ?? const []) (h as num).toInt()];
  List<int> get _holes => holesOfRound(_firstHole, _holesPlanned, _skipped);
  List<int>? get _pars {
    final holes = (widget.round['course'] as Map?)?['holes'] as List?;
    if (holes == null) return null;
    return [for (final h in holes) ((h as Map)['par'] as num).toInt()];
  }

  int _parOf(int hole) {
    final pars = _pars;
    return pars != null && hole >= 1 && hole <= pars.length ? pars[hole - 1] : 4;
  }

  String get _maxMode => ((widget.round['scoring'] as Map?)?['maxScore'] as Map?)?['mode'] as String? ?? 'doublePar';
  int? get _maxValue => (((widget.round['scoring'] as Map?)?['maxScore'] as Map?)?['value'] as num?)?.toInt();
  int _maxOf(int hole) => maxScoreFor(_maxMode, _maxValue, _parOf(hole));

  List<ScoreRow> _rows(QuerySnapshot<Map<String, dynamic>>? snap) => [
    for (final d in snap?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
      if (d.data()['playerId'] is String && d.data()['hole'] is num && d.data()['strokes'] is num)
        ScoreRow(
          playerId: d.data()['playerId'] as String,
          hole: (d.data()['hole'] as num).toInt(),
          strokes: (d.data()['strokes'] as num).toInt(),
          kind: (d.data()['kind'] as String?) ?? 'played',
          clientTime: ((d.data()['clientTime'] as num?) ?? 0).toInt(),
        ),
  ];

  // A save is one small write to the inbox. It is not awaited: with no signal the write waits on the phone and
  // goes when the connection returns, and the row says so. A refusal by the security rules shows at once.
  void _save(String playerId, String groupId, int hole, int strokes, String kind) {
    final time = DateTime.now().millisecondsSinceEpoch;
    _round
        .collection('submissions')
        .doc(submissionDocId(playerId, hole, time))
        .set({
          'playerId': playerId,
          'hole': hole,
          'strokes': strokes,
          'kind': kind,
          'groupId': groupId,
          'enteredBy': widget.uid,
          'clientTime': time,
        })
        .catchError((Object e) {
          if (mounted) showErrorMessage(context, 'Could not save that score: $e');
        });
    setState(() => _draft.remove('$playerId|$hole'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _groups,
      builder: (context, groupSnap) {
        if (groupSnap.hasError) return Text('${groupSnap.error}', style: TextStyle(color: theme.colorScheme.error));
        final groups = groupSnap.data?.docs ?? [];
        if (groupSnap.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        }
        if (groups.isEmpty) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('This round has no groups yet. Set them on the Rounds tab.'));
        }
        final mine = groups.where((g) => (g.data()['playerIds'] as List).contains(widget.uid)).firstOrNull;
        // A player enters for their own group; an organizer can pick any group.
        final group = groups.where((g) => g.id == _groupId).firstOrNull ?? mine ?? (widget.isAdmin ? groups.first : null);
        if (group == null) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text("You are not in a group for this round, so there is nothing for you to score."));
        }
        final groupIds = List<String>.from(group.data()['playerIds'] as List);
        final allIds = [for (final g in groups) ...List<String>.from(g.data()['playerIds'] as List)];
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _scores,
          builder: (context, scoreSnap) {
            if (scoreSnap.hasError) return Text('${scoreSnap.error}', style: TextStyle(color: theme.colorScheme.error));
            final latest = latestScores(_rows(scoreSnap.data));
            final holes = _holes;
            // Start on the first hole this group has not finished.
            if (_hole == null && scoreSnap.hasData) {
              _hole = holes.firstWhere(
                (h) => groupIds.any((p) => latest[p]?[h] == null),
                orElse: () => holes.last,
              );
            }
            final hole = _hole ?? holes.first;
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _mine,
              builder: (context, mineSnap) {
                final subs = mineSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.isAdmin && groups.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DropdownButtonFormField<String>(
                          initialValue: group.id,
                          decoration: const InputDecoration(labelText: 'Group'),
                          items: [
                            for (final g in groups)
                              DropdownMenuItem(value: g.id, child: Text('Group ${g.data()['order']}${g.id == mine?.id ? ' (yours)' : ''}')),
                          ],
                          onChanged: (id) => setState(() {
                            _groupId = id;
                            _hole = null;
                          }),
                        ),
                      ),
                    if (_pars == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('This round has no course yet, so par is assumed to be 4. Add a course in Round settings.', style: theme.textTheme.bodySmall),
                      ),
                    _HoleBar(
                      holes: holes,
                      hole: hole,
                      par: _parOf(hole),
                      note: _maxMode == 'none'
                          ? 'No maximum in this round: enter every real stroke.'
                          : 'Most you can score here: ${_maxOf(hole)}. Pickup records exactly ${_maxOf(hole)}.',
                      done: {for (final h in holes) h: groupIds.every((p) => latest[p]?[h] != null)},
                      onPick: (h) => setState(() => _hole = h),
                    ),
                    const SizedBox(height: 8),
                    for (final playerId in groupIds)
                      _PlayerEntry(
                        key: ValueKey('$playerId|$hole'),
                        playerId: playerId,
                        isMe: playerId == widget.uid,
                        teeNote: _teeNote(playerId, hole),
                        par: _parOf(hole),
                        max: _maxOf(hole),
                        noPickups: _maxMode == 'none',
                        saved: latest[playerId]?[hole],
                        draft: _draft['$playerId|$hole'],
                        submissionState: _stateOf(subs, playerId, hole, latest[playerId]?[hole]),
                        onDraft: (n) => setState(() => _draft['$playerId|$hole'] = n),
                        onSave: (n) => _save(playerId, group.id, hole, n, 'played'),
                        onPickup: () => _save(playerId, group.id, hole, _maxOf(hole), 'pickup'),
                      ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: holes.indexOf(hole) > 0 ? () => setState(() => _hole = holes[holes.indexOf(hole) - 1]) : null,
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('Previous hole'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: holes.indexOf(hole) < holes.length - 1 ? () => setState(() => _hole = holes[holes.indexOf(hole) + 1]) : null,
                          icon: const Icon(Icons.chevron_right),
                          label: const Text('Next hole'),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    _Scoreboard(ids: allIds, latest: latest, holes: holes, pars: _pars ?? [for (var i = 0; i < 18; i++) 4], myId: widget.uid),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // What happened to the last thing I sent for this player and hole: still on the phone, with the server, or
  // turned away (with the reason). Null when there is nothing to say.
  _SubState? _stateOf(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> subs,
    String playerId,
    int hole,
    ScoreRow? saved,
  ) {
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    for (final s in subs) {
      final d = s.data();
      if (d['playerId'] != playerId || (d['hole'] as num?)?.toInt() != hole) continue;
      if (last == null || ((d['clientTime'] as num?) ?? 0) > ((last.data()['clientTime'] as num?) ?? 0)) last = s;
    }
    if (last == null) return null;
    final d = last.data();
    if (last.metadata.hasPendingWrites) return const _SubState('Not sent yet. It will go when you have signal.', _Tone.warn);
    if (d['outcome'] == null) return const _SubState('Sending...', _Tone.warn);
    if (d['outcome'] == 'rejected') {
      // A turned-away score only matters while it is the newest word on this hole.
      final newerSaved = saved != null && saved.clientTime > ((d['clientTime'] as num?) ?? 0).toInt();
      if (newerSaved) return null;
      return _SubState('Not saved: ${d['reason'] ?? d['reasonCode']}', _Tone.bad);
    }
    if (d['outcome'] == 'accepted_late') return _SubState('${d['reason']}', _Tone.warn);
    return null;
  }
}

enum _Tone { warn, bad }

class _SubState {
  const _SubState(this.text, this.tone);
  final String text;
  final _Tone tone;
}

// The hole picker: the current hole, its par, and a chip per hole (ticked once everyone in the group has one).
class _HoleBar extends StatelessWidget {
  const _HoleBar({required this.holes, required this.hole, required this.par, required this.note, required this.done, required this.onPick});

  final List<int> holes;
  final int hole;
  final int par;
  final String note;
  final Map<int, bool> done;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hole $hole · Par $par', style: theme.textTheme.titleLarge),
        Text(note, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final h in holes)
              ChoiceChip(
                label: Text('$h'),
                avatar: done[h] == true ? const Icon(Icons.check, size: 16) : null,
                selected: h == hole,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onPick(h),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlayerEntry extends StatelessWidget {
  const _PlayerEntry({
    super.key,
    required this.playerId,
    required this.isMe,
    required this.teeNote,
    required this.par,
    required this.max,
    required this.noPickups,
    required this.saved,
    required this.draft,
    required this.submissionState,
    required this.onDraft,
    required this.onSave,
    required this.onPickup,
  });

  final String playerId;
  final bool isMe;
  final String? teeNote;
  final int par;
  final int max;
  final bool noPickups;
  final ScoreRow? saved;
  final int? draft;
  final _SubState? submissionState;
  final ValueChanged<int> onDraft;
  final ValueChanged<int> onSave;
  final VoidCallback onPickup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = draft ?? saved?.strokes ?? par;
    final over = value > max;
    final unchanged = saved != null && !saved!.isPickup && saved!.strokes == value && draft == null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FutureBuilder<String>(
                    future: playerNameOf(playerId),
                    builder: (context, snap) => Text('${snap.data ?? '...'}${isMe ? ' (you)' : ''}', style: theme.textTheme.titleMedium),
                  ),
                ),
                Text(
                  saved == null ? 'No score yet' : (saved!.isPickup ? 'Saved: pickup (${saved!.strokes})' : 'Saved: ${saved!.strokes}'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (teeNote != null) Text(teeNote!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: value > 1 ? () => onDraft(value - 1) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 72,
                  child: Text('$value', textAlign: TextAlign.center, style: theme.textTheme.displaySmall),
                ),
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: value < maxStrokes ? () => onDraft(value + 1) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: over || unchanged ? null : () => onSave(value),
                    child: Text(saved == null ? 'Save $value' : 'Change to $value'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: noPickups || (saved?.isPickup ?? false) ? null : onPickup,
                  child: Text(noPickups ? 'No pickups' : 'Pickup ($max)'),
                ),
              ],
            ),
            if (over)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Over this round\'s maximum of $max on a par $par. Use Pickup, or change the round\'s maximum.', style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (submissionState != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  submissionState!.text,
                  style: TextStyle(color: submissionState!.tone == _Tone.bad ? theme.colorScheme.error : Colors.orange.shade800),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Everyone in the round: thru, total, to par, and a hole-by-hole grid. A pickup shows with a star.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.ids, required this.latest, required this.holes, required this.pars, required this.myId});

  final List<String> ids;
  final Map<String, Map<int, ScoreRow>> latest;
  final List<int> holes;
  final List<int> pars;
  final String myId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = [
      for (final id in ids.toSet())
        (
          id: id,
          total: totalFor(latest[id]),
          par: parOfScoredHoles(latest[id], pars),
        ),
    ]..sort((a, b) {
        if (a.total.holes == 0 && b.total.holes == 0) return 0;
        if (a.total.holes == 0) return 1;
        if (b.total.holes == 0) return -1;
        return (a.total.strokes - a.par).compareTo(b.total.strokes - b.par);
      });
    return FutureBuilder<List<String>>(
      future: Future.wait([for (final e in entries) playerNameOf(e.id)]),
      builder: (context, snap) {
        final names = snap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scoreboard', style: theme.textTheme.titleLarge),
            Text('Gross strokes, live. * = pickup, recorded as the round maximum.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (names == null)
              const LinearProgressIndicator()
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 12,
                  horizontalMargin: 8,
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 36,
                  columns: [
                    const DataColumn(label: Text('Player')),
                    const DataColumn(label: Text('Thru')),
                    const DataColumn(label: Text('Tot')),
                    const DataColumn(label: Text('+/-')),
                    for (final h in holes) DataColumn(label: Text('$h')),
                  ],
                  rows: [
                    for (var i = 0; i < entries.length; i++)
                      DataRow(
                        cells: [
                          DataCell(Text('${names[i]}${entries[i].id == myId ? ' (you)' : ''}')),
                          DataCell(Text('${entries[i].total.holes}')),
                          DataCell(Text(entries[i].total.holes == 0 ? '-' : '${entries[i].total.strokes}')),
                          DataCell(Text(entries[i].total.holes == 0 ? '-' : toParLabel(entries[i].total.strokes, entries[i].par))),
                          for (final h in holes) DataCell(_cell(latest[entries[i].id]?[h], h, theme)),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _cell(ScoreRow? row, int hole, ThemeData theme) {
    if (row == null) return const Text('');
    final par = hole >= 1 && hole <= pars.length ? pars[hole - 1] : 4;
    final color = row.strokes < par ? Colors.green.shade700 : (row.strokes > par ? theme.colorScheme.error : null);
    return Text('${row.strokes}${row.isPickup ? '*' : ''}', style: TextStyle(color: color, fontWeight: row.strokes < par ? FontWeight.bold : null));
  }
}
