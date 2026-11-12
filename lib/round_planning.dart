// Small pure helpers for the Rounds screen of the debug harness: no Flutter, no Firebase, so they are
// unit tested with plain data.

/// How many holes a round plays and where it starts, from the three choices the screen offers.
/// `18` is all holes, `front` the front nine (holes 1 to 9), `back` the back nine (holes 10 to 18).
class HolesChoice {
  const HolesChoice(this.holesPlanned, this.firstHole);

  final int holesPlanned;
  final int firstHole;

  static const all = HolesChoice(18, 1);
  static const front = HolesChoice(9, 1);
  static const back = HolesChoice(9, 10);

  static HolesChoice fromKey(String key) => switch (key) {
    'front' => front,
    'back' => back,
    _ => all,
  };

  static String keyOf(int holesPlanned, int firstHole) {
    if (holesPlanned == 9) return firstHole == 10 ? 'back' : 'front';
    return '18';
  }

  /// Plain words for a round's holes: "18 holes", "Front 9" or "Back 9".
  static String label(int holesPlanned, int firstHole) => switch (keyOf(
    holesPlanned,
    firstHole,
  )) {
    'front' => 'Front 9',
    'back' => 'Back 9',
    _ => '18 holes',
  };
}

/// Splits [items] into groups of at most [maxSize], as evenly as possible, never leaving a lone
/// straggler when it can be avoided: 10 players with a limit of 4 become 4 + 3 + 3, not 4 + 4 + 2.
List<List<T>> evenChunks<T>(List<T> items, int maxSize) {
  if (items.isEmpty || maxSize < 1) return [];
  final groupCount = (items.length + maxSize - 1) ~/ maxSize;
  final base = items.length ~/ groupCount;
  final extra = items.length % groupCount;
  final chunks = <List<T>>[];
  var start = 0;
  for (var i = 0; i < groupCount; i++) {
    final size = base + (i < extra ? 1 : 0);
    chunks.add(items.sublist(start, start + size));
    start += size;
  }
  return chunks;
}

const _samplePars = [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4];
// Odd numbers on the front nine and even numbers on the back, the usual pattern; each used once.
const _sampleStrokeIndex = [7, 11, 15, 3, 9, 1, 17, 5, 13, 8, 12, 16, 4, 10, 2, 18, 6, 14];

/// A made-up 18-hole par-72 course, so a round can be set up for testing without typing 18 holes.
/// It is in the shape the createRound function takes.
Map<String, Object?> sampleCourse() => {
  'name': 'Sample Course',
  'tees': 'White',
  'rating': 71.5,
  'slope': 125,
  'holes': [
    for (var i = 0; i < 18; i++)
      {
        'par': _samplePars[i],
        'strokeIndex': _sampleStrokeIndex[i],
        'yards': 300 + i * 10,
      },
  ],
};

/// A tee time as the exact instant the server wants: the local date and time on this phone, written
/// in UTC ("2026-11-14T19:30:00.000Z").
String teeTimeToIso(String roundDate, int hour, int minute) {
  final parts = roundDate.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2], hour, minute).toUtc().toIso8601String();
}
