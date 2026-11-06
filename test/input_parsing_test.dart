import 'package:flutter_test/flutter_test.dart';
import 'package:golf_app_client/input_parsing.dart';

void main() {
  group('parseHandicap', () {
    test('an empty box means clear the handicap', () {
      for (final text in ['', '   ']) {
        final parsed = parseHandicap(text);
        expect(parsed.ok, isTrue, reason: 'text: "$text"');
        expect(parsed.value, isNull);
      }
    });

    test(
      'accepts numbers inside the range, including both ends and decimals',
      () {
        expect(parseHandicap('12').value, 12);
        expect(parseHandicap(' 12.34 ').value, 12.34);
        expect(parseHandicap('-10').value, -10);
        expect(parseHandicap('54').value, 54);
        expect(parseHandicap('0').value, 0);
      },
    );

    test(
      'rejects text that is not a number instead of treating it as empty',
      () {
        for (final text in [
          'abc',
          '12abc',
          '1,5',
          'NaN',
          'Infinity',
          '--3',
          '.',
        ]) {
          final parsed = parseHandicap(text);
          expect(parsed.ok, isFalse, reason: 'text: "$text"');
          expect(parsed.error, 'Handicap must be a number from -10 to 54');
        }
      },
    );

    test('rejects numbers outside the range', () {
      for (final text in ['-11', '55', '-10.1', '54.1', '1000']) {
        expect(parseHandicap(text).ok, isFalse, reason: 'text: "$text"');
      }
    });
  });

  group('parseWagerPot', () {
    test('an empty box means no pot', () {
      expect(parseWagerPot('').ok, isTrue);
      expect(parseWagerPot('').value, isNull);
    });

    test('accepts amounts from 0 to 100000', () {
      expect(parseWagerPot('0').value, 0);
      expect(parseWagerPot('250.456').value, 250.456);
      expect(parseWagerPot('100000').value, 100000);
    });

    test('rejects text, negatives and amounts over the limit', () {
      for (final text in ['abc', '-5', '100001', '12 dollars', 'NaN']) {
        final parsed = parseWagerPot(text);
        expect(parsed.ok, isFalse, reason: 'text: "$text"');
        expect(parsed.error, 'Wager pot must be a number from 0 to 100000');
      }
    });
  });
}
