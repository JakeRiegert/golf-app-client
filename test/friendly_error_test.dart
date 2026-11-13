import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_app_client/dialog_utils.dart';

void main() {
  test('a transport failure becomes one plain sentence', () {
    for (final e in [
      FirebaseFunctionsException(code: 'internal', message: 'internal [0]'),
      FirebaseFunctionsException(code: 'internal', message: 'internal'),
      FirebaseFunctionsException(code: 'unavailable', message: 'unavailable'),
      FirebaseFunctionsException(code: 'deadline-exceeded', message: ''),
    ]) {
      expect(friendlyError(e), "Couldn't reach the server. Check your connection and try again.");
    }
  });

  test('a readable server message is kept as it is', () {
    final e = FirebaseFunctionsException(code: 'failed-precondition', message: 'Course and holes cannot change once scores exist.');
    expect(friendlyError(e), 'Course and holes cannot change once scores exist.');
  });

  test('a trailing status number the SDK adds is dropped', () {
    final e = FirebaseFunctionsException(code: 'failed-precondition', message: 'Group 1 has 2 players, more than 1. Move players first. [400]');
    expect(friendlyError(e), 'Group 1 has 2 players, more than 1. Move players first.');
  });

  test('a refusal with no text falls back to its code', () {
    expect(friendlyError(FirebaseFunctionsException(code: 'permission-denied', message: '')), 'permission-denied');
  });
}
