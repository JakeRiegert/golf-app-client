import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

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
      FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('createTournament');

  Query<Map<String, dynamic>> get _mine => FirebaseFirestore.instance
      .collection('tournaments')
      .where('organizerId', isEqualTo: widget.uid);

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
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
          _status = 'Created "${data['name']}" - invite code ${data['inviteCode']}';
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
          'Goes through the createTournament function. Dates are optional (YYYY-MM-DD).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Tournament name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _start,
                decoration: const InputDecoration(labelText: 'Start date', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _end,
                decoration: const InputDecoration(labelText: 'End date', border: OutlineInputBorder()),
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
        Text('Your tournaments', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Live from Firestore (tournaments you organize).', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _mine.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('${snapshot.error}', style: TextStyle(color: theme.colorScheme.error));
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return const Text('None yet.');
            return Column(
              children: [for (final doc in docs) _TournamentTile(doc: doc)],
            );
          },
        ),
      ],
    );
  }
}

class _TournamentTile extends StatelessWidget {
  const _TournamentTile({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final dates = [data['startDate'], data['endDate']].whereType<String>().join(' to ');
    return Card(
      child: ListTile(
        title: Text('${data['name']}'),
        subtitle: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: doc.reference.collection('private').doc('settings').snapshots(),
          builder: (context, snapshot) {
            final code = snapshot.data?.data()?['inviteCode'] ?? '-';
            return Text(
              '${data['visibility']} - ${data['status']}'
              '${dates.isEmpty ? '' : ' - $dates'}\n'
              'Invite code: $code',
            );
          },
        ),
        isThreeLine: true,
      ),
    );
  }
}
