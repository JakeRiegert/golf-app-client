import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_app_client/date_field.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  group('DateField.parse and format', () {
    test('round-trips the API format', () {
      expect(DateField.format(DateTime(2026, 11, 4)), '2026-11-04');
      expect(DateField.parse('2026-11-04'), DateTime(2026, 11, 4));
      expect(DateField.parse(' 2026-11-04 '), DateTime(2026, 11, 4));
    });

    test('treats anything else as no date', () {
      expect(DateField.parse(''), isNull);
      expect(DateField.parse('11/04/2026'), isNull);
      expect(DateField.parse('2026-1-4'), isNull);
    });
  });

  group('DateField', () {
    testWidgets('picks a date from the calendar and writes it as YYYY-MM-DD', (
      tester,
    ) async {
      final controller = TextEditingController(text: '2026-11-04');
      await tester.pumpWidget(
        host(DateField(controller: controller, label: 'Start date')),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await tester.tap(find.text('15'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(controller.text, '2026-11-15');
    });

    testWidgets('cancelling leaves the value alone', (tester) async {
      final controller = TextEditingController(text: '2026-11-04');
      await tester.pumpWidget(
        host(DateField(controller: controller, label: 'Start date')),
      );

      await tester.tap(find.byTooltip('Pick Start date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.text, '2026-11-04');
    });

    testWidgets('clears the date, which means no date', (tester) async {
      final controller = TextEditingController(text: '2026-11-04');
      await tester.pumpWidget(
        host(DateField(controller: controller, label: 'End date')),
      );

      await tester.tap(find.byTooltip('Clear End date'));
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(
        find.byTooltip('Clear End date'),
        findsNothing,
      ); // nothing left to clear
    });

    testWidgets('the end date cannot be picked before the start date', (
      tester,
    ) async {
      final start = TextEditingController(text: '2026-11-10');
      final end = TextEditingController();
      await tester.pumpWidget(
        host(DateField(controller: end, label: 'End date', notBefore: start)),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      // The picker opens on the start date, and an earlier day is disabled.
      await tester.tap(find.text('5'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(end.text, '2026-11-10');

      // A later day is fine.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(end.text, '2026-11-20');
    });
  });
}
