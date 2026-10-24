import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

// Debug-harness slice for teams inside one tournament: a live list read from Firestore, an
// "add team" row (createTeams) and a rename dialog (updateTeam). Only the tournament's
// organizer or co-admin can write; everyone else gets the function's permission-denied error.
class TeamsSection extends StatefulWidget {
  const TeamsSection({
    super.key,
    required this.tournamentId,
    required this.canEdit,
  });

  final String tournamentId;

  // Only organizers and co-admins can change teams (the functions enforce it; this just hides
  // the controls from everyone else).
  final bool canEdit;

  @override
  State<TeamsSection> createState() => _TeamsSectionState();
}

class _TeamsSectionState extends State<TeamsSection> {
  final _name = TextEditingController();
  final _color = TextEditingController();
  bool _busy = false;
  String? _error;

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  CollectionReference<Map<String, dynamic>> get _teams => FirebaseFirestore
      .instance
      .collection('tournaments')
      .doc(widget.tournamentId)
      .collection('teams');

  @override
  void dispose() {
    _name.dispose();
    _color.dispose();
    super.dispose();
  }

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

  Future<void> _addTeam() => _run(() async {
    await _functions.httpsCallable('createTeams').call({
      'tournamentId': widget.tournamentId,
      'teams': [
        {
          'name': _name.text,
          if (_color.text.trim().isNotEmpty) 'color': _color.text.trim(),
        },
      ],
    });
    _name.clear();
    _color.clear();
  });

  Future<void> _rename(String teamId, String current) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: current),
    );
    if (name == null) return;
    await _run(() async {
      await _functions.httpsCallable('updateTeam').call({
        'tournamentId': widget.tournamentId,
        'teamId': teamId,
        'name': name,
      });
    });
  }

  Color? _parseColor(Object? hex) {
    if (hex is! String || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
      return null;
    }
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Teams', style: theme.textTheme.titleSmall),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _teams.orderBy('createdAt').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                '${snapshot.error}',
                style: TextStyle(color: theme.colorScheme.error),
              );
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return const Text('No teams yet.');
            return Column(
              children: [
                for (final doc in docs)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 10,
                      backgroundColor:
                          _parseColor(doc.data()['color']) ??
                          theme.disabledColor,
                    ),
                    title: Text('${doc.data()['name']}'),
                    subtitle: Text('${doc.data()['color'] ?? 'no color'}'),
                    trailing: widget.canEdit
                        ? TextButton(
                            onPressed: _busy
                                ? null
                                : () =>
                                      _rename(doc.id, '${doc.data()['name']}'),
                            child: const Text('Rename'),
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
        if (widget.canEdit) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Team name',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _color,
                  decoration: const InputDecoration(
                    labelText: '#RRGGBB',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _addTeam,
                child: const Text('Add'),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

// Owns its own controller so it is disposed only after the dialog has finished animating out
// (disposing it from the caller while the route is closing trips a framework assertion).
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename team'),
      content: TextField(controller: _controller, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
