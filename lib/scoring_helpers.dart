// Small pure helpers for the Score page of the debug harness: no Flutter, no Firebase, so they are unit
// tested with plain data.

/// The document id of a score submission. It is fixed by the content (player, hole, phone time), which is
/// what the security rule requires and what makes a retried write the same document, never a duplicate.
String submissionDocId(String playerId, int hole, int clientTimeMs) => '${playerId}_${hole}_$clientTimeMs';

/// One official score as read from Firestore.
class ScoreRow {
  const ScoreRow({
    required this.playerId,
    required this.hole,
    required this.strokes,
    required this.kind,
    required this.clientTime,
  });

  final String playerId;
  final int hole;
  final int strokes;
  final String kind; // 'played' or 'pickup'
  final int clientTime;

  bool get isPickup => kind == 'pickup';
}

/// The score that counts for each player and hole. Corrections are new entries, never edits, so when a hole
/// has several the one with the latest phone time wins (ties go to the larger id order, which is stable).
Map<String, Map<int, ScoreRow>> latestScores(Iterable<ScoreRow> rows) {
  final result = <String, Map<int, ScoreRow>>{};
  for (final row in rows) {
    final holes = result.putIfAbsent(row.playerId, () => {});
    final current = holes[row.hole];
    if (current == null || row.clientTime >= current.clientTime) holes[row.hole] = row;
  }
  return result;
}

/// Total strokes over the holes that have a score, and how many holes that is.
({int strokes, int holes}) totalFor(Map<int, ScoreRow>? holes) {
  var strokes = 0;
  var count = 0;
  for (final row in (holes ?? const <int, ScoreRow>{}).values) {
    strokes += row.strokes;
    count += 1;
  }
  return (strokes: strokes, holes: count);
}

/// Par of the holes that have a score, so a total can be shown against par ("+3").
int parOfScoredHoles(Map<int, ScoreRow>? holes, List<int> parByHole) {
  var par = 0;
  for (final hole in (holes ?? const <int, ScoreRow>{}).keys) {
    if (hole >= 1 && hole <= parByHole.length) par += parByHole[hole - 1];
  }
  return par;
}

/// "E", "+3" or "-2".
String toParLabel(int strokes, int par) {
  final diff = strokes - par;
  if (diff == 0) return 'E';
  return diff > 0 ? '+$diff' : '$diff';
}

/// Reads "4 4 3 5 ..." (separated by spaces, commas or new lines) as one par per hole. Returns the pars, or
/// an error sentence to show. Each par is 3 to 6, the usual range; the server is still the authority.
({List<int>? pars, String? error}) parsePars(String text, {int count = 18}) {
  final parts = text.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
  if (parts.length != count) {
    return (pars: null, error: 'Enter $count pars, one per hole (you entered ${parts.length}).');
  }
  final pars = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 3 || value > 6) {
      return (pars: null, error: 'Each par must be a whole number from 3 to 6 ("$part" is not).');
    }
    pars.add(value);
  }
  return (pars: pars, error: null);
}

/// A course in the shape createRound and updateRound take, from a name and one par per hole. The stroke
/// index defaults to the hole number: it only matters for net scoring, which comes later.
Map<String, Object?> courseFromPars(String name, List<int> pars) => {
  'name': name.trim().isEmpty ? 'My course' : name.trim(),
  'holes': [
    for (var i = 0; i < pars.length; i++) {'par': pars[i], 'strokeIndex': i + 1},
  ],
};

/// The holes a round plays, in order (the course may list 18 while the round is one nine).
List<int> holesOfRound(int firstHole, int holesPlanned, List<int> skipped) => [
  for (var h = firstHole; h < firstHole + holesPlanned; h++)
    if (!skipped.contains(h)) h,
];

/// The app-wide cap on one hole's strokes (the same number the server and the security rule use).
const int maxStrokes = 30;

/// The most a played score on a hole can be, from the round's maximum-score setting and the hole's par: double
/// par by default, par + 2 for "double bogey", a fixed number, or only the app-wide cap for "none". The server
/// does the same sum and is the authority; this only lets the screen say so before a score is sent.
int maxScoreFor(String mode, int? fixedValue, int par) {
  final raw = switch (mode) {
    'doubleBogey' => par + 2,
    'fixed' => fixedValue ?? maxStrokes,
    'none' => maxStrokes,
    _ => par * 2,
  };
  return raw > maxStrokes ? maxStrokes : raw;
}
