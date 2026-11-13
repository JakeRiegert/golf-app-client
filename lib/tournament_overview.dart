import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'date_field.dart';
import 'dialog_utils.dart';
import 'input_parsing.dart';

// The Overview page of a tournament: who you are in it, its state, the invite code, and (for admins) the
// Edit, Start and Reopen actions. Teams, players and rounds each have their own page.
class TournamentOverview extends StatelessWidget {
  const TournamentOverview({
    super.key,
    required this.tournamentId,
    required this.uid,
    required this.data,
  });

  final String tournamentId;
  final String uid;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOrganizer = data['organizerId'] == uid;
    final isAdmin = isOrganizer || data['coAdminId'] == uid;
    final role = isOrganizer ? 'organizer' : (isAdmin ? 'co-admin' : 'player');
    final started = data['startedAt'] != null;
    final dates = [data['startDate'], data['endDate']].whereType<String>().join(' to ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${data['name']}', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line('You', role),
                _Line('Status', started ? 'Started (players can no longer change their team or handicap)' : 'Not started (players can still pick their team and handicap)'),
                _Line('Who can watch', data['visibility'] == 'public' ? 'Public: anyone signed in' : 'Private: members only'),
                if (dates.isNotEmpty) _Line('Dates', dates),
                if (data['wagerPotAmount'] is num) _Line('Team pot', '\$${data['wagerPotAmount']}'),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('tournaments')
                      .doc(tournamentId)
                      .collection('private')
                      .doc('settings')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final code = snapshot.data?.data()?['inviteCode'] as String?;
                    return Row(
                      children: [
                        Expanded(child: _Line('Invite code', code ?? '-')),
                        if (code != null)
                          IconButton(
                            tooltip: 'Copy the invite code',
                            icon: const Icon(Icons.copy),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: code));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(const SnackBar(content: Text('Invite code copied')));
                              }
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 12),
          AdminActions(tournamentId: tournamentId, data: data, started: started),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          SelectableText(value),
        ],
      ),
    );
  }
}

// Admin-only actions on a tournament card: Edit (updateTournament), Start (startTournament) and
// Reopen (updateTournament with started: false). Start and Reopen ask first, since they change
// whether players can edit their own handicap.
class AdminActions extends StatefulWidget {
  const AdminActions({
    super.key,
    required this.tournamentId,
    required this.data,
    required this.started,
  });

  final String tournamentId;
  final Map<String, dynamic> data;
  final bool started;

  @override
  State<AdminActions> createState() => AdminActionsState();
}

class AdminActionsState extends State<AdminActions> {
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
      if (mounted) {
        setState(() => _error = friendlyError(e));
        showErrorMessage(context, friendlyError(e));
      }
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
            onPressed: () => popDialog(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => popDialog(context, true),
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
      builder: (context) => EditTournamentDialog(data: widget.data),
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
class EditTournamentDialog extends StatefulWidget {
  const EditTournamentDialog({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  State<EditTournamentDialog> createState() => EditTournamentDialogState();
}

class EditTournamentDialogState extends State<EditTournamentDialog> {
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
  String? _potError;

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
    // Text that is not a number is an error to show, never "no pot" (which would clear it).
    final pot = parseWagerPot(_pot.text);
    if (!pot.ok) {
      setState(() => _potError = pot.error);
      return;
    }
    popDialog(context, <String, Object?>{
      'name': _name.text,
      'startDate': orNull(_start),
      'endDate': orNull(_end),
      'wagerPotAmount': pot.value,
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
                decoration: InputDecoration(
                  labelText: 'Team wager pot (optional)',
                  errorText: _potError,
                ),
                onChanged: (_) {
                  if (_potError != null) setState(() => _potError = null);
                },
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
          onPressed: () => popDialog(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
