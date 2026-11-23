import 'package:flutter_test/flutter_test.dart';
import 'package:golf_app_client/checkin_panel.dart';

void main() {
  group('who completed a check-in', () {
    test('the player themselves is not "by organizer"', () {
      expect(CheckInPanel.byOrganizer('p1', {'checkedIn': true, 'checkedInBy': 'p1'}), isFalse);
    });

    test('someone else checking them in is "by organizer"', () {
      expect(CheckInPanel.byOrganizer('p1', {'checkedIn': true, 'checkedInBy': 'org'}), isTrue);
    });

    test('not checked in, or an older entry with no record of who, is never "by organizer"', () {
      expect(CheckInPanel.byOrganizer('p1', {'checkedIn': false, 'checkedInBy': 'org'}), isFalse);
      expect(CheckInPanel.byOrganizer('p1', {'checkedIn': true}), isFalse);
      expect(CheckInPanel.byOrganizer('p1', null), isFalse);
    });
  });
}
