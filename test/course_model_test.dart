import 'package:flutter_test/flutter_test.dart';
import 'package:golf_app_client/course_model.dart';

CourseDraft complete() {
  final draft = CourseDraft(name: ' Four Bridges ');
  for (var i = 0; i < holeCount; i++) {
    draft.par[i] = i == 2 ? 3 : 4;
    draft.strokeIndex[i] = i + 1;
  }
  draft.tees.add(TeeDraft(id: 't1', name: 'Blue', yards: List<int?>.generate(holeCount, (i) => 350 + i), menRating: 71.2, menSlope: 128, womenRating: 76.4, womenSlope: 130));
  return draft;
}

void main() {
  test('a complete course has no problems and builds the payload the server takes', () {
    final draft = complete();
    expect(draft.problems(), isEmpty);
    final payload = draft.toPayload();
    expect(payload['name'], 'Four Bridges');
    final holes = payload['holes'] as List;
    expect(holes, hasLength(18));
    expect(holes[2], {'par': 3, 'strokeIndex': 3});
    final tee = (payload['tees'] as List).single as Map;
    expect(tee['id'], 't1');
    expect(tee['men'], {'rating': 71.2, 'slope': 128});
    expect(tee['women'], {'rating': 76.4, 'slope': 130});
    expect((tee['yards'] as List)[17], 367);
  });

  test("the women's ranking and par are sent only when entered", () {
    final draft = complete();
    for (var i = 0; i < holeCount; i++) {
      draft.strokeIndexWomen[i] = ((i * 7) % 18) + 1;
    }
    draft.parWomen[2] = 4;
    expect(draft.problems(), isEmpty);
    final holes = draft.toPayload()['holes'] as List;
    expect(holes[2], {'par': 3, 'parWomen': 4, 'strokeIndex': 3, 'strokeIndexWomen': 15});
    expect(holes[0], {'par': 4, 'strokeIndex': 1, 'strokeIndexWomen': 1});
    expect(draft.womenParDiffers, isTrue);
  });

  test('says what is wrong, in sentences', () {
    final draft = complete();
    draft.name = '  ';
    draft.par[0] = 7;
    draft.strokeIndex[5] = 1; // a repeat of hole 1's ranking
    final problems = draft.problems().join(' | ');
    expect(problems, contains('name'));
    expect(problems, contains('Par must be 3 to 6'));
    expect(problems, contains("Men's HCP uses [1] more than once"));
  });

  test("a partly filled women's ranking is refused, an empty one is fine", () {
    final draft = complete();
    expect(draft.problems(), isEmpty);
    draft.strokeIndexWomen[0] = 5;
    expect(draft.problems().join(), contains("Women's HCP needs a number"));
  });

  test('tee checks: names, paired rating and slope, ranges', () {
    final draft = complete();
    draft.tees.add(TeeDraft(id: 't2', name: 'blue', menRating: 70.0));
    final problems = draft.problems().join(' | ');
    expect(problems, contains('Two tees are named blue'));
    expect(problems, contains("give both the men's rating and slope"));
    draft.tees.last
      ..name = 'Red'
      ..menSlope = 300
      ..womenRating = 20
      ..womenSlope = 120;
    final again = draft.problems().join(' | ');
    expect(again, contains("men's slope must be 55 to 155"));
    expect(again, contains("women's rating must be 50 to 90"));
  });

  test('marks the holes whose ranking number is repeated', () {
    expect(CourseDraft.duplicateRankingHoles([1, 2, 3, 2, null]), {2, 4});
    expect(CourseDraft.duplicateRankingHoles([1, 2, 3]), isEmpty);
    expect(CourseDraft.duplicateRankingHoles([19, 2]), {1});
  });

  test('picks an unused tee id', () {
    final draft = complete();
    expect(draft.nextTeeId(), 't2');
    draft.tees.add(TeeDraft(id: 't2', name: 'White'));
    draft.tees.removeAt(0); // only t2 is left, and the next id must not collide with it
    final next = draft.nextTeeId();
    expect(draft.tees.any((t) => t.id == next), isFalse);
  });

  group('reading a stored course', () {
    test('a course with tee sets round-trips', () {
      final stored = complete().toPayload();
      final back = CourseDraft.fromStored(stored);
      expect(back.name, 'Four Bridges');
      expect(back.par[2], 3);
      expect(back.tees.single.name, 'Blue');
      expect(back.tees.single.womenSlope, 130);
      expect(back.toPayload(), stored);
    });

    test('the older single-tee shape becomes one tee', () {
      final stored = {
        'name': 'Sample Course',
        'tees': 'White',
        'rating': 71.5,
        'slope': 125,
        'holes': [
          for (var i = 0; i < 18; i++) {'par': 4, 'strokeIndex': i + 1, 'yards': 300 + i},
        ],
      };
      final draft = CourseDraft.fromStored(stored);
      expect(draft.tees.single, isA<TeeDraft>());
      expect(draft.tees.single.name, 'White');
      expect(draft.tees.single.menSlope, 125);
      expect(draft.tees.single.yards[3], 303);
    });

    test('a course with no tee information has none, and no course gives an empty draft', () {
      final bare = CourseDraft.fromStored({
        'name': 'Muni',
        'tees': null,
        'holes': [
          for (var i = 0; i < 18; i++) {'par': 4, 'strokeIndex': i + 1, 'yards': null},
        ],
      });
      expect(bare.tees, isEmpty);
      expect(CourseDraft.fromStored(null).name, '');
    });
  });

  group('the one-line course summary', () {
    test('counts tees and the par of the holes played', () {
      final course = complete().toPayload();
      expect(courseLine(course), 'Four Bridges · 1 tee · par 71');
      expect(courseLine(course, firstHole: 1, holesPlanned: 9), 'Four Bridges · 1 tee · par 35');
      expect(courseLine(null), 'No course yet');
      final legacy = {
        'name': 'Sample',
        'tees': 'White',
        'holes': [
          for (var i = 0; i < 18; i++) {'par': 4},
        ],
      };
      expect(courseLine(legacy), 'Sample · 1 tee · par 72');
    });
  });
}
