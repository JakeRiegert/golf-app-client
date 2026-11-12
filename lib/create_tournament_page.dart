import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'date_field.dart';
import 'dialog_utils.dart';

// A page of its own for making a tournament (createTournament). When it succeeds the page closes and
// hands back the new tournament's details, so the list can show the invite code.
class CreateTournamentPage extends StatefulWidget {
  const CreateTournamentPage({super.key});

  @override
  State<CreateTournamentPage> createState() => _CreateTournamentPageState();
}

class _CreateTournamentPageState extends State<CreateTournamentPage> {
  final _name = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  bool _public = false;
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('createTournament').call({
        'name': _name.text,
        if (_start.text.trim().isNotEmpty) 'startDate': _start.text.trim(),
        if (_end.text.trim().isNotEmpty) 'endDate': _end.text.trim(),
        'visibility': _public ? 'public' : 'private',
      });
      if (mounted) Navigator.of(context).pop(Map<String, dynamic>.from(result.data as Map));
    } on FirebaseFunctionsException catch (e) {
      if (mounted) showErrorMessage(context, e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New tournament')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Tournament name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DateField(controller: _start, label: 'Start date (optional)', border: const OutlineInputBorder()),
                const SizedBox(height: 12),
                DateField(controller: _end, label: 'End date (optional)', notBefore: _start, border: const OutlineInputBorder()),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Public'),
                  subtitle: const Text('Anyone signed in can watch. Joining still needs the invite code.'),
                  value: _public,
                  onChanged: (v) => setState(() => _public = v),
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: _creating ? null : _create, child: const Text('Create tournament')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
