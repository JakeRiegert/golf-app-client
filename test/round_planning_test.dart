import 'package:flutter_test/flutter_test.dart';
import 'package:golf_app_client/round_planning.dart';

void main() {
  group('HolesChoice', () {
    test('maps the three choices to holes and a first hole', () {
      expect(HolesChoice.fromKey('18').holesPlanned, 18);
      expect(HolesChoice.fromKey('front').holesPlanned, 9);
      expect(HolesChoice.fromKey('front').firstHole, 1);
      expect(HolesChoice.fromKey('back').holesPlanned, 9);
      expect(HolesChoice.fromKey('back').firstHole, 10);
    });

    test('round-trips and describes a round in plain words', () {
      expect(HolesChoice.keyOf(18, 1), '18');
      expect(HolesChoice.keyOf(9, 1), 'front');
      expect(HolesChoice.keyOf(9, 10), 'back');
      expect(HolesChoice.label(18, 1), '18 holes');
      expect(HolesChoice.label(9, 1), 'Front 9');
      expect(HolesChoice.label(9, 10), 'Back 9');
    });
  });

  group('evenChunks', () {
    List<int> sizes(int players, int max) => evenChunks(List.generate(players, (i) => i), max).map((c) => c.length).toList();

    test('spreads the remainder instead of leaving a straggler', () {
      expect(sizes(10, 4), [4, 3, 3]);
      expect(sizes(9, 4), [3, 3, 3]);
      expect(sizes(5, 4), [3, 2]);
      expect(sizes(13, 4), [4, 3, 3, 3]);
    });

    test('fills full groups when the roster divides evenly', () {
      expect(sizes(8, 4), [4, 4]);
      expect(sizes(4, 4), [4]);
    });

    test('handles small and empty rosters and never exceeds the limit', () {
      expect(sizes(1, 4), [1]);
      expect(sizes(0, 4), isEmpty);
      expect(sizes(7, 1), [1, 1, 1, 1, 1, 1, 1]);
      for (var players = 1; players <= 40; players++) {
        for (var max = 1; max <= 8; max++) {
          final chunks = sizes(players, max);
          expect(chunks.every((size) => size >= 1 && size <= max), isTrue, reason: '$players players, max $max');
          expect(chunks.fold<int>(0, (a, b) => a + b), players);
          expect(chunks.reduce((a, b) => a > b ? a : b) - chunks.reduce((a, b) => a < b ? a : b) <= 1, isTrue);
        }
      }
    });

    test('keeps every item exactly once, in order', () {
      final chunks = evenChunks(['a', 'b', 'c', 'd', 'e'], 4);
      expect(chunks.expand((c) => c).toList(), ['a', 'b', 'c', 'd', 'e']);
    });
  });

  group('sampleCourse', () {
    test('is a valid 18-hole par-72 course with each stroke index used once', () {
      final course = sampleCourse();
      final holes = (course['holes'] as List).cast<Map<String, Object?>>();
      expect(holes, hasLength(18));
      expect(holes.map((h) => h['par'] as int).reduce((a, b) => a + b), 72);
      expect(holes.map((h) => h['strokeIndex']).toSet(), {for (var i = 1; i <= 18; i++) i});
      expect(holes.every((h) => (h['par'] as int) >= 3 && (h['par'] as int) <= 6), isTrue);
      expect(course['name'], isNotEmpty);
    });
  });

  group('teeTimeToIso', () {
    test('writes the local date and time as a UTC instant the server accepts', () {
      final iso = teeTimeToIso('2026-11-14', 13, 30);
      expect(iso, endsWith('Z'));
      expect(DateTime.parse(iso), DateTime(2026, 11, 14, 13, 30).toUtc());
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$').hasMatch(iso), isTrue);
    });
  });
}
