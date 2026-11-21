import 'package:flutter_test/flutter_test.dart';
import 'package:golf_app_client/scoring_helpers.dart';

ScoreRow row(String p, int hole, int strokes, int time, {String kind = 'played'}) =>
    ScoreRow(playerId: p, hole: hole, strokes: strokes, kind: kind, clientTime: time);

void main() {
  test('the submission id is player, hole and phone time', () {
    expect(submissionDocId('u1', 4, 1700000000000), 'u1_4_1700000000000');
  });

  test('the latest phone time wins for a player and hole; other holes and players are kept', () {
    final latest = latestScores([
      row('a', 1, 5, 100),
      row('a', 1, 4, 200), // a correction
      row('a', 2, 6, 150),
      row('b', 1, 3, 90),
    ]);
    expect(latest['a']![1]!.strokes, 4);
    expect(latest['a']![2]!.strokes, 6);
    expect(latest['b']![1]!.strokes, 3);
    // An older entry arriving later does not replace a newer one.
    final late = latestScores([row('a', 1, 4, 200), row('a', 1, 9, 100)]);
    expect(late['a']![1]!.strokes, 4);
  });

  test('totals count only holes with a score, and par follows those holes', () {
    final latest = latestScores([row('a', 1, 5, 1), row('a', 3, 4, 2, kind: 'pickup')]);
    expect(totalFor(latest['a']), (strokes: 9, holes: 2));
    expect(totalFor(null), (strokes: 0, holes: 0));
    final pars = [4, 4, 3, 5];
    expect(parOfScoredHoles(latest['a'], pars), 7);
    expect(toParLabel(9, 7), '+2');
    expect(toParLabel(7, 7), 'E');
    expect(toParLabel(5, 7), '-2');
    expect(latest['a']![3]!.isPickup, isTrue);
  });

  test('pars are read from spaces, commas or lines, and checked', () {
    final ok = parsePars('4 4 3 5, 4 4 3 5\n4 4 4 3 5 4 4 3 5 4');
    expect(ok.error, isNull);
    expect(ok.pars, hasLength(18));
    expect(parsePars('4 4 3').error, contains('18'));
    expect(parsePars('4 4 3 5 4 4 3 5 4 4 4 3 5 4 4 3 5 9').error, contains('3 to 6'));
    expect(parsePars('4 4 3 5 4 4 3 5 4 4 4 3 5 4 4 3 5 x').error, contains('3 to 6'));
    expect(parsePars('4 3 5', count: 3).pars, [4, 3, 5]);
  });

  test('a course from pars has one hole per par and a stroke index', () {
    final course = courseFromPars('  Pine Hills ', [4, 3, 5]);
    expect(course['name'], 'Pine Hills');
    expect(course['holes'], [
      {'par': 4, 'strokeIndex': 1},
      {'par': 3, 'strokeIndex': 2},
      {'par': 5, 'strokeIndex': 3},
    ]);
    expect(courseFromPars('', [4])['name'], 'My course');
  });

  test('the holes of a round follow the first hole, the count and skipped holes', () {
    expect(holesOfRound(1, 9, []), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(holesOfRound(10, 9, [12]), [10, 11, 13, 14, 15, 16, 17, 18]);
    expect(holesOfRound(1, 18, []), hasLength(18));
  });

  test('the maximum follows the round setting and never passes the app-wide cap', () {
    expect(maxScoreFor('doublePar', null, 4), 8);
    expect(maxScoreFor('doublePar', null, 5), 10);
    expect(maxScoreFor('doubleBogey', null, 4), 6);
    expect(maxScoreFor('fixed', 7, 4), 7);
    expect(maxScoreFor('none', null, 4), 30);
    expect(maxScoreFor('doublePar', null, 20), 30);
  });
}
