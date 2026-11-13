import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'date_field.dart';
import 'dialog_utils.dart';
import 'round_planning.dart';

// The Rounds page of a tournament (debug harness): a live list of its rounds, each with its groups,
// read from Firestore; every change goes through the createRound, updateRound and setGroups functions.
// Only the organizer and co-admin see the controls; everyone else sees the same information read-only,
// with their own group marked. The functions enforce all of it; the screen only hides what you cannot do.

FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: 'us-central1');

// Display names are read once per person and remembered, so a long group list does not re-read profiles.
final Map<String, Future<String>> _names = {};

Future<String> _nameOf(String uid) => _names.putIfAbsent(uid, () async {
  try {
    final snap = await FirebaseFirestore.instance.collection('players').doc(uid).get();
    final name = (snap.data()?['displayName'] as String?)?.trim();
    return (name == null || name.isEmpty) ? 'Player ${uid.substring(0, min(4, uid.length))}' : name;
  } catch (_) {
    return 'Player ${uid.substring(0, min(4, uid.length))}';
  }
});

void _showDone(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.green.shade700));
}

Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => popDialog(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => popDialog(context, true), child: Text(action)),
      ],
    ),
  );
  return result == true;
}

// Calls a function and shows the outcome where it is seen at once. A round dated outside the tournament's
// dates is refused by the server until the admin agrees to widen them, so that one refusal becomes a
// question and a retry. Returns whether the call went through.
Future<bool> _call(BuildContext context, String name, Map<String, Object?> payload, {String? done}) async {
  try {
    try {
      await _functions.httpsCallable(name).call(payload);
    } on FirebaseFunctionsException catch (e) {
      final needsAgreement = e.code == 'failed-precondition' && (e.message ?? '').contains('extendTournamentDates');
      if (!needsAgreement || !context.mounted) rethrow;
      final agreed = await _confirm(
        context,
        'Widen the tournament dates?',
        'This date is outside the tournament dates. Widen them to include it? Everyone is told.',
        'Widen and continue',
      );
      if (!agreed) return false;
      await _functions.httpsCallable(name).call({...payload, 'extendTournamentDates': true});
    }
    if (context.mounted && done != null) _showDone(context, done);
    return true;
  } on FirebaseFunctionsException catch (e) {
    if (context.mounted) showErrorMessage(context, friendlyError(e));
    return false;
  }
}

class RoundsSection extends StatefulWidget {
  const RoundsSection({super.key, required this.tournamentId, required this.uid, required this.canEdit});

  final String tournamentId;
  final String uid;
  final bool canEdit;

  @override
  State<RoundsSection> createState() => _RoundsSectionState();
}

class _RoundsSectionState extends State<RoundsSection> {
  bool _busy = false;

  CollectionReference<Map<String, dynamic>> get _rounds =>
      FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).collection('rounds');

  Future<void> _add() async {
    final values = await showDialog<_RoundValues>(context: context, builder: (_) => const _RoundDialog());
    if (values == null || !mounted) return;
    setState(() => _busy = true);
    await _call(context, 'createRound', {
      'tournamentId': widget.tournamentId,
      ...values.toPayload(),
      if (values.useSampleCourse) 'course': sampleCourse(),
    }, done: 'Round added.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Rounds', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          widget.canEdit
              ? 'One playing day each. Add rounds any time, even after the tournament has started.'
              : 'The playing days, and who you play with.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (widget.canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add a round'),
            ),
          ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _rounds.orderBy('number').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('${snapshot.error}', style: TextStyle(color: theme.colorScheme.error));
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No rounds yet.'));
            }
            return Column(
              children: [
                for (final doc in docs)
                  _RoundCard(
                    key: ValueKey(doc.id),
                    tournamentId: widget.tournamentId,
                    roundId: doc.id,
                    data: doc.data(),
                    uid: widget.uid,
                    canEdit: widget.canEdit,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RoundCard extends StatefulWidget {
  const _RoundCard({
    super.key,
    required this.tournamentId,
    required this.roundId,
    required this.data,
    required this.uid,
    required this.canEdit,
  });

  final String tournamentId;
  final String roundId;
  final Map<String, dynamic> data;
  final String uid;
  final bool canEdit;

  @override
  State<_RoundCard> createState() => _RoundCardState();
}

class _RoundCardState extends State<_RoundCard> {
  bool _busy = false;

  DocumentReference<Map<String, dynamic>> get _tournament =>
      FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId);

  DocumentReference<Map<String, dynamic>> get _round => _tournament.collection('rounds').doc(widget.roundId);

  Map<String, dynamic> get _course => Map<String, dynamic>.from((widget.data['course'] as Map?) ?? {});
  bool get _hasCourse => widget.data['course'] != null;
  bool get _hasSampleCourse => _course['name'] == 'Sample Course';
  int get _maxGroupSize => (widget.data['maxGroupSize'] as num?)?.toInt() ?? 4;
  int get _firstHole => (widget.data['firstHole'] as num?)?.toInt() ?? 1;
  int get _holesPlanned => (widget.data['holesPlanned'] as num?)?.toInt() ?? 18;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSettings() async {
    final values = await showDialog<_RoundValues>(
      context: context,
      builder: (_) => _RoundDialog(initial: widget.data),
    );
    if (values == null || !mounted) return;
    await _run(() async {
      await _call(context, 'updateRound', {
        'tournamentId': widget.tournamentId,
        'roundId': widget.roundId,
        ...values.toPayload(),
        // The sample course is only touched when the switch changed; a hand-entered course is left alone.
        if (values.useSampleCourse && !_hasSampleCourse) 'course': sampleCourse(),
        if (!values.useSampleCourse && _hasSampleCourse) 'course': null,
      }, done: 'Round updated.');
    });
  }

  // Replace the groups from the roster: everyone not withdrawn, in groups of at most the round's size.
  Future<void> _fill({required bool randomize, required bool hasGroups}) async {
    if (hasGroups) {
      final ok = await _confirm(
        context,
        'Replace the groups?',
        'The current groups, with their tee times, are replaced by new ones.',
        'Replace',
      );
      if (!ok || !mounted) return;
    }
    await _run(() async {
      final roster = await _tournament.collection('players').get();
      final ids = [for (final doc in roster.docs) if (doc.data()['withdrawn'] != true) doc.id];
      if (ids.isEmpty) {
        if (mounted) showErrorMessage(context, 'There is nobody on the roster yet.');
        return;
      }
      if (randomize) ids.shuffle(Random());
      final chunks = evenChunks(ids, _maxGroupSize);
      if (!mounted) return;
      await _call(context, 'setGroups', {
        'tournamentId': widget.tournamentId,
        'roundId': widget.roundId,
        'groups': [for (final chunk in chunks) {'playerIds': chunk}],
      }, done: '${chunks.length} group${chunks.length == 1 ? '' : 's'} set.');
    });
  }

  Future<void> _clear() async {
    final ok = await _confirm(context, 'Remove all groups?', 'Every group in this round is removed.', 'Remove');
    if (!ok || !mounted) return;
    await _run(() async {
      await _call(context, 'setGroups', {
        'tournamentId': widget.tournamentId,
        'roundId': widget.roundId,
        'groups': <Object?>[],
      }, done: 'Groups removed.');
    });
  }

  // The group payload the server takes, rebuilt from what is stored.
  Map<String, Object?> _groupPayload(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final teeTime = data['teeTime'];
    final sides = data['sides'];
    return {
      'id': doc.id,
      'playerIds': List<String>.from(data['playerIds'] as List),
      'teeHole': (data['teeHole'] as num).toInt(),
      'teeTime': teeTime is Timestamp ? teeTime.toDate().toUtc().toIso8601String() : null,
      'sides': sides is List
          ? [for (final side in sides) {'playerIds': List<String>.from((side as Map)['playerIds'] as List)}]
          : null,
    };
  }

  Future<void> _editGroup(List<QueryDocumentSnapshot<Map<String, dynamic>>> groups, int index) async {
    final doc = groups[index];
    final edit = await showDialog<_GroupEdit>(
      context: context,
      builder: (_) => _GroupDialog(
        roundDate: widget.data['date'] as String,
        firstHole: _firstHole,
        lastHole: _firstHole + _holesPlanned - 1,
        skipped: List<int>.from(((widget.data['skippedHoles'] as List?) ?? []).map((h) => (h as num).toInt())),
        initialHole: (doc.data()['teeHole'] as num).toInt(),
        initialTeeTime: (doc.data()['teeTime'] as Timestamp?)?.toDate().toLocal(),
      ),
    );
    if (edit == null || !mounted) return;
    await _run(() async {
      final payload = [for (final g in groups) _groupPayload(g)];
      payload[index] = {...payload[index], 'teeHole': edit.teeHole, 'teeTime': edit.teeTimeIso};
      await _call(context, 'setGroups', {
        'tournamentId': widget.tournamentId,
        'roundId': widget.roundId,
        'groups': payload,
      }, done: 'Group ${index + 1} updated.');
    });
  }

  String _courseText() {
    if (!_hasCourse) return 'No course yet';
    final all = (_course['holes'] as List?) ?? const [];
    // Only the holes this round plays: the course may list 18 while the round is a front or back nine.
    final from = (_firstHole - 1).clamp(0, all.length);
    final to = (_firstHole - 1 + _holesPlanned).clamp(from, all.length);
    final par = all.sublist(from, to).fold<int>(0, (total, h) => total + ((h as Map)['par'] as num).toInt());
    return '${_course['name']} (par $par)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = (widget.data['status'] as String?) ?? 'scheduled';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Round ${widget.data['number']} · ${widget.data['date']}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(status), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${HolesChoice.label(_holesPlanned, _firstHole)} · groups of up to $_maxGroupSize\n'
              'Course: ${_courseText()}',
              style: theme.textTheme.bodyMedium,
            ),
            if (widget.canEdit)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _editSettings,
                  icon: const Icon(Icons.tune),
                  label: const Text('Round settings'),
                ),
              ),
            const Divider(height: 24),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _round.collection('groups').orderBy('order').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('${snapshot.error}', style: TextStyle(color: theme.colorScheme.error));
                }
                final groups = snapshot.data?.docs ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Groups (${groups.length})', style: theme.textTheme.titleSmall)),
                        if (widget.canEdit)
                          PopupMenuButton<String>(
                            enabled: !_busy,
                            tooltip: 'Fill groups',
                            onSelected: (choice) {
                              if (choice == 'clear') {
                                _clear();
                              } else {
                                _fill(randomize: choice == 'random', hasGroups: groups.isNotEmpty);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'order', child: Text('Fill from the roster, in order')),
                              const PopupMenuItem(value: 'random', child: Text('Fill from the roster, shuffled')),
                              if (groups.isNotEmpty) const PopupMenuItem(value: 'clear', child: Text('Remove all groups')),
                            ],
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [Text('Set groups'), Icon(Icons.arrow_drop_down)]),
                            ),
                          ),
                      ],
                    ),
                    if (groups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          widget.canEdit ? 'No groups yet. Use "Set groups" to fill them from the roster.' : 'No groups yet.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    for (var i = 0; i < groups.length; i++)
                      _GroupTile(
                        order: (groups[i].data()['order'] as num).toInt(),
                        data: groups[i].data(),
                        uid: widget.uid,
                        onEdit: widget.canEdit && !_busy ? () => _editGroup(groups, i) : null,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.order, required this.data, required this.uid, required this.onEdit});

  final int order;
  final Map<String, dynamic> data;
  final String uid;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playerIds = List<String>.from(data['playerIds'] as List);
    final mine = playerIds.contains(uid);
    final teeTime = data['teeTime'];
    final tee = teeTime is Timestamp ? TimeOfDay.fromDateTime(teeTime.toDate().toLocal()).format(context) : null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: mine ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        title: Text(
          'Group $order${mine ? ' (your group)' : ''}',
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                tee == null ? 'No tee time' : 'Tee time $tee (this phone\'s time)',
                'starts on hole ${data['teeHole']}',
              ].join(' · '),
            ),
            FutureBuilder<List<String>>(
              future: Future.wait([for (final id in playerIds) _nameOf(id)]),
              builder: (context, snapshot) {
                final names = snapshot.data;
                if (names == null) return const Text('...');
                return Text([for (var i = 0; i < names.length; i++) playerIds[i] == uid ? '${names[i]} (you)' : names[i]].join(', '));
              },
            ),
          ],
        ),
        isThreeLine: true,
        trailing: onEdit == null ? null : IconButton(tooltip: 'Edit tee time and start hole', icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
      ),
    );
  }
}

// What the add-round and round-settings dialog hands back.
class _RoundValues {
  const _RoundValues({required this.date, required this.holesKey, required this.maxGroupSize, required this.useSampleCourse});

  final String date;
  final String holesKey;
  final int maxGroupSize;
  final bool useSampleCourse;

  Map<String, Object?> toPayload() {
    final holes = HolesChoice.fromKey(holesKey);
    return {
      'date': date,
      'holesPlanned': holes.holesPlanned,
      'firstHole': holes.firstHole,
      'maxGroupSize': maxGroupSize,
    };
  }
}

class _RoundDialog extends StatefulWidget {
  const _RoundDialog({this.initial});

  // The round being edited, or null when adding one.
  final Map<String, dynamic>? initial;

  @override
  State<_RoundDialog> createState() => _RoundDialogState();
}

class _RoundDialogState extends State<_RoundDialog> {
  late final _date = TextEditingController(text: (widget.initial?['date'] as String?) ?? '');
  late String _holes = HolesChoice.keyOf(
    (widget.initial?['holesPlanned'] as num?)?.toInt() ?? 18,
    (widget.initial?['firstHole'] as num?)?.toInt() ?? 1,
  );
  late int _size = (widget.initial?['maxGroupSize'] as num?)?.toInt() ?? 4;
  late bool _sample = widget.initial == null || ((widget.initial?['course'] as Map?)?['name'] == 'Sample Course');
  String? _error;

  // A hand-entered course is not touched from here, so the switch is hidden for one.
  bool get _courseIsOther {
    final course = widget.initial?['course'] as Map?;
    return course != null && course['name'] != 'Sample Course';
  }

  @override
  void initState() {
    super.initState();
    // The message about a missing date goes away as soon as a date is picked.
    _date.addListener(() {
      if (_error != null && DateField.parse(_date.text) != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  void _save() {
    if (DateField.parse(_date.text) == null) {
      setState(() => _error = 'Pick the date of the round');
      return;
    }
    popDialog(
      context,
      _RoundValues(date: _date.text.trim(), holesKey: _holes, maxGroupSize: _size, useSampleCourse: _sample && !_courseIsOther),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add a round' : 'Round settings'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DateField(controller: _date, label: 'Date'),
              const SizedBox(height: 16),
              const Text('Holes'),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '18', label: Text('18')),
                  ButtonSegment(value: 'front', label: Text('Front 9')),
                  ButtonSegment(value: 'back', label: Text('Back 9')),
                ],
                selected: {_holes},
                onSelectionChanged: (s) => setState(() => _holes = s.first),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _size,
                decoration: const InputDecoration(labelText: 'Largest group'),
                items: [for (var n = 1; n <= 8; n++) DropdownMenuItem(value: n, child: Text('$n players'))],
                onChanged: (n) => setState(() => _size = n ?? 4),
              ),
              if (!_courseIsOther)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use the sample course'),
                  subtitle: const Text('A made-up par-72 course, for testing'),
                  value: _sample,
                  onChanged: (v) => setState(() => _sample = v),
                ),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => popDialog(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: Text(widget.initial == null ? 'Add round' : 'Save')),
      ],
    );
  }
}

class _GroupEdit {
  const _GroupEdit(this.teeTimeIso, this.teeHole);

  final String? teeTimeIso;
  final int teeHole;
}

// Tee time and starting hole for one group. A different starting hole is a shotgun start.
class _GroupDialog extends StatefulWidget {
  const _GroupDialog({
    required this.roundDate,
    required this.firstHole,
    required this.lastHole,
    required this.skipped,
    required this.initialHole,
    required this.initialTeeTime,
  });

  final String roundDate;
  final int firstHole;
  final int lastHole;
  final List<int> skipped;
  final int initialHole;
  final DateTime? initialTeeTime;

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  late TimeOfDay? _time = widget.initialTeeTime == null ? null : TimeOfDay.fromDateTime(widget.initialTeeTime!);
  late int _hole = widget.initialHole;

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0));
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    final holes = [for (var h = widget.firstHole; h <= widget.lastHole; h++) if (!widget.skipped.contains(h)) h];
    return AlertDialog(
      title: const Text('Tee time and start hole'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(_time == null ? 'Set a tee time' : _time!.format(context)),
                ),
                if (_time != null) TextButton(onPressed: () => setState(() => _time = null), child: const Text('No tee time')),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'On ${widget.roundDate}, in this phone\'s time zone.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: holes.contains(_hole) ? _hole : holes.first,
              decoration: const InputDecoration(labelText: 'Starts on hole'),
              items: [for (final h in holes) DropdownMenuItem(value: h, child: Text('Hole $h'))],
              onChanged: (h) => setState(() => _hole = h ?? widget.firstHole),
            ),
            const SizedBox(height: 4),
            Text(
              'Any hole other than ${widget.firstHole} is a shotgun start: the group plays on from there and wraps around.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => popDialog(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => popDialog(
            context,
            _GroupEdit(_time == null ? null : teeTimeToIso(widget.roundDate, _time!.hour, _time!.minute), _hole),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
