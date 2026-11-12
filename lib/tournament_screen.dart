import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'players_section.dart';
import 'rounds_section.dart';
import 'teams_section.dart';
import 'tournament_overview.dart';

// One tournament, split into pages (tabs) so a phone shows one thing at a time:
// Overview (state, invite code, Start/Edit), Teams, Players and Rounds.
class TournamentScreen extends StatelessWidget {
  const TournamentScreen({super.key, required this.tournamentId, required this.uid});

  final String tournamentId;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final tournament = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tournament.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Rules refuse non-admins a suspended tournament, so this is what a member sees.
          return Scaffold(
            appBar: AppBar(title: const Text('Tournament unavailable')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('It may be suspended.\n${snapshot.error}'),
            ),
          );
        }
        final data = snapshot.data?.data();
        if (data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final isAdmin = data['organizerId'] == uid || data['coAdminId'] == uid;
        final started = data['startedAt'] != null;
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text('${data['name']}', overflow: TextOverflow.ellipsis),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Teams'),
                  Tab(text: 'Players'),
                  Tab(text: 'Rounds'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _Page(child: TournamentOverview(tournamentId: tournamentId, uid: uid, data: data)),
                _Page(child: TeamsSection(tournamentId: tournamentId, canEdit: isAdmin)),
                _Page(
                  child: PlayersSection(
                    tournamentId: tournamentId,
                    uid: uid,
                    canEdit: isAdmin,
                    started: started,
                    organizerId: data['organizerId'] as String?,
                    coAdminId: data['coAdminId'] as String?,
                  ),
                ),
                _Page(child: RoundsSection(tournamentId: tournamentId, uid: uid, canEdit: isAdmin)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// A scrolling page with a readable width, so a tablet or a laptop is not one very wide column.
class _Page extends StatelessWidget {
  const _Page({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}
