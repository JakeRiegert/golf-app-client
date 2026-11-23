// A course as the Course page edits it, and as createRound / updateRound take it (docs/rounds-data-model.md 2.1b):
// a par and two hole-ranking rows (men's and women's stroke index) for each hole, plus any number of tee sets, each
// with its own yardage and its own men's and women's rating and slope. Plain Dart, no Flutter, so it is unit tested.

const int holeCount = 18;

class TeeDraft {
  TeeDraft({
    required this.id,
    required this.name,
    List<int?>? yards,
    this.menRating,
    this.menSlope,
    this.womenRating,
    this.womenSlope,
  }) : yards = yards ?? List<int?>.filled(holeCount, null);

  final String id;
  String name;
  List<int?> yards;
  double? menRating;
  int? menSlope;
  double? womenRating;
  int? womenSlope;

  int get yardsEntered => yards.where((y) => y != null).length;
  int get totalYards => yards.fold<int>(0, (sum, y) => sum + (y ?? 0));
  bool get hasMen => menRating != null && menSlope != null;
  bool get hasWomen => womenRating != null && womenSlope != null;
}

class CourseDraft {
  CourseDraft({
    this.name = '',
    List<int?>? par,
    List<int?>? parWomen,
    List<int?>? strokeIndex,
    List<int?>? strokeIndexWomen,
    List<TeeDraft>? tees,
  }) : par = par ?? List<int?>.filled(holeCount, null),
       parWomen = parWomen ?? List<int?>.filled(holeCount, null),
       strokeIndex = strokeIndex ?? List<int?>.filled(holeCount, null),
       strokeIndexWomen = strokeIndexWomen ?? List<int?>.filled(holeCount, null),
       tees = tees ?? [];

  String name;
  List<int?> par;
  // null on a hole means the women's par is the same as the men's.
  List<int?> parWomen;
  List<int?> strokeIndex;
  // Left empty everywhere means the women's ranking is the same as the men's.
  List<int?> strokeIndexWomen;
  List<TeeDraft> tees;

  bool get womenParDiffers => parWomen.any((p) => p != null);

  /// Par of the holes entered so far, for the running total.
  int get totalPar => par.fold<int>(0, (sum, p) => sum + (p ?? 0));

  /// A new tee id that no tee of this course uses yet.
  String nextTeeId() {
    var n = tees.length + 1;
    while (tees.any((t) => t.id == 't$n')) {
      n++;
    }
    return 't$n';
  }

  /// Reads a course as stored on a round. Older rounds stored one tee as top-level text, rating, slope and yards on
  /// each hole; that becomes a single tee here. A missing course gives an empty draft.
  factory CourseDraft.fromStored(Map? stored) {
    final draft = CourseDraft();
    if (stored == null) return draft;
    draft.name = '${stored['name'] ?? ''}';
    final holes = (stored['holes'] as List?) ?? const [];
    int? intOf(Object? v) => v is num ? v.toInt() : null;
    for (var i = 0; i < holeCount && i < holes.length; i++) {
      final h = holes[i] as Map;
      draft.par[i] = intOf(h['par']);
      draft.parWomen[i] = intOf(h['parWomen']);
      draft.strokeIndex[i] = intOf(h['strokeIndex']);
      draft.strokeIndexWomen[i] = intOf(h['strokeIndexWomen']);
    }
    final tees = stored['tees'];
    if (tees is List) {
      for (final raw in tees) {
        final t = raw as Map;
        final yards = (t['yards'] as List?) ?? const [];
        final men = t['men'] as Map?;
        final women = t['women'] as Map?;
        draft.tees.add(
          TeeDraft(
            id: '${t['id']}',
            name: '${t['name']}',
            yards: [for (var i = 0; i < holeCount; i++) i < yards.length ? intOf(yards[i]) : null],
            menRating: (men?['rating'] as num?)?.toDouble(),
            menSlope: intOf(men?['slope']),
            womenRating: (women?['rating'] as num?)?.toDouble(),
            womenSlope: intOf(women?['slope']),
          ),
        );
      }
    } else {
      final legacyYards = [for (var i = 0; i < holeCount; i++) i < holes.length ? intOf((holes[i] as Map)['yards']) : null];
      final hasName = tees is String && tees.trim().isNotEmpty;
      final rating = (stored['rating'] as num?)?.toDouble();
      final slope = intOf(stored['slope']);
      if (hasName || rating != null || slope != null || legacyYards.any((y) => y != null)) {
        draft.tees.add(
          TeeDraft(id: 't1', name: hasName ? tees.trim() : 'Default', yards: legacyYards, menRating: rating, menSlope: slope),
        );
      }
    }
    return draft;
  }

  /// Everything wrong with the course, each as a sentence for the screen; empty when it can be saved. The server
  /// checks the same things and is the authority.
  List<String> problems() {
    final out = <String>[];
    if (name.trim().isEmpty) out.add('Give the course a name.');
    final badPar = [for (var i = 0; i < holeCount; i++) if (par[i] == null || par[i]! < 3 || par[i]! > 6) i + 1];
    if (badPar.isNotEmpty) out.add('Par must be 3 to 6 on every hole (check hole ${badPar.take(4).join(', ')}${badPar.length > 4 ? '...' : ''}).');
    final badParW = [for (var i = 0; i < holeCount; i++) if (parWomen[i] != null && (parWomen[i]! < 3 || parWomen[i]! > 6)) i + 1];
    if (badParW.isNotEmpty) out.add("Women's par must be 3 to 6 (check hole ${badParW.take(4).join(', ')}).");
    out.addAll(_rankingProblems(strokeIndex, "Men's HCP", required: true));
    if (strokeIndexWomen.any((s) => s != null)) out.addAll(_rankingProblems(strokeIndexWomen, "Women's HCP", required: false));
    final names = <String>{};
    for (final tee in tees) {
      final label = tee.name.trim().isEmpty ? 'A tee' : 'Tee ${tee.name.trim()}';
      if (tee.name.trim().isEmpty) out.add('Every tee needs a name.');
      if (!names.add(tee.name.trim().toLowerCase()) && tee.name.trim().isNotEmpty) out.add('Two tees are named ${tee.name.trim()}.');
      if ((tee.menRating == null) != (tee.menSlope == null)) out.add("$label: give both the men's rating and slope, or neither.");
      if ((tee.womenRating == null) != (tee.womenSlope == null)) out.add("$label: give both the women's rating and slope, or neither.");
      if (tee.menRating != null && (tee.menRating! < 50 || tee.menRating! > 90)) out.add("$label: men's rating must be 50 to 90.");
      if (tee.womenRating != null && (tee.womenRating! < 50 || tee.womenRating! > 90)) out.add("$label: women's rating must be 50 to 90.");
      if (tee.menSlope != null && (tee.menSlope! < 55 || tee.menSlope! > 155)) out.add("$label: men's slope must be 55 to 155.");
      if (tee.womenSlope != null && (tee.womenSlope! < 55 || tee.womenSlope! > 155)) out.add("$label: women's slope must be 55 to 155.");
      if (tee.yards.any((y) => y != null && (y < 1 || y > 1000))) out.add('$label: yards must be 1 to 1000.');
    }
    return out;
  }

  List<String> _rankingProblems(List<int?> row, String label, {required bool required}) {
    final out = <String>[];
    final missing = [for (var i = 0; i < holeCount; i++) if (row[i] == null) i + 1];
    if (missing.isNotEmpty && (required || missing.length != holeCount)) {
      out.add('$label needs a number from 1 to 18 on every hole (missing: hole ${missing.take(4).join(', ')}${missing.length > 4 ? '...' : ''}).');
    }
    final seen = <int>{};
    final dupes = <int>{};
    for (final v in row) {
      if (v == null) continue;
      if (v < 1 || v > holeCount) {
        out.add('$label must use 1 to 18 only.');
        break;
      }
      if (!seen.add(v)) dupes.add(v);
    }
    if (dupes.isNotEmpty) out.add('$label uses ${dupes.toList()..sort()} more than once.');
    return out;
  }

  /// The hole numbers (1-based) whose ranking number is used twice or out of range, so the screen can mark them.
  static Set<int> duplicateRankingHoles(List<int?> row) {
    final firstSeen = <int, int>{};
    final marked = <int>{};
    for (var i = 0; i < row.length; i++) {
      final v = row[i];
      if (v == null) continue;
      if (v < 1 || v > holeCount) {
        marked.add(i + 1);
        continue;
      }
      final earlier = firstSeen[v];
      if (earlier != null) {
        marked.add(earlier + 1);
        marked.add(i + 1);
      } else {
        firstSeen[v] = i;
      }
    }
    return marked;
  }

  /// The payload for createRound / updateRound. Call only when problems() is empty.
  Map<String, Object?> toPayload() => {
    'name': name.trim(),
    'holes': [
      for (var i = 0; i < holeCount; i++)
        {
          'par': par[i],
          if (parWomen[i] != null) 'parWomen': parWomen[i],
          'strokeIndex': strokeIndex[i],
          if (strokeIndexWomen.every((s) => s != null)) 'strokeIndexWomen': strokeIndexWomen[i],
        },
    ],
    'tees': [
      for (final tee in tees)
        {
          'id': tee.id,
          'name': tee.name.trim(),
          'yards': tee.yards,
          if (tee.hasMen) 'men': {'rating': tee.menRating, 'slope': tee.menSlope},
          if (tee.hasWomen) 'women': {'rating': tee.womenRating, 'slope': tee.womenSlope},
        },
    ],
  };
}

/// One line about a stored course for a round card or the round page: "Four Bridges · 3 tees · par 72".
/// [holes] limits the par to the holes the round plays.
String courseLine(Map? course, {int firstHole = 1, int holesPlanned = 18}) {
  if (course == null) return 'No course yet';
  final all = (course['holes'] as List?) ?? const [];
  final from = (firstHole - 1).clamp(0, all.length);
  final to = (firstHole - 1 + holesPlanned).clamp(from, all.length);
  final par = all.sublist(from, to).fold<int>(0, (sum, h) => sum + ((h as Map)['par'] as num).toInt());
  final tees = course['tees'];
  final teeCount = tees is List ? tees.length : (tees is String && tees.trim().isNotEmpty ? 1 : 0);
  final teeText = teeCount == 0 ? '' : ' · $teeCount ${teeCount == 1 ? 'tee' : 'tees'}';
  return '${course['name']}$teeText · par $par';
}
