import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golf_app_client/dialog_utils.dart';

Widget app(Future<void> Function(BuildContext context) onOpen) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => onOpen(context),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'a second close during the exit animation does not pop the page underneath',
    (tester) async {
      await tester.pumpWidget(
        app(
          (context) => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Dialog'),
              actions: [
                TextButton(
                  // Two quick taps: the second arrives while the dialog is still animating out.
                  onPressed: () {
                    popDialog(dialogContext);
                    popDialog(dialogContext);
                  },
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Dialog'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Dialog'), findsNothing);
      expect(
        find.text('Open'),
        findsOneWidget,
        reason: 'the page underneath must survive',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('returns the value of the first close and ignores a later one', (
    tester,
  ) async {
    Object? result = 'unset';
    await tester.pumpWidget(
      app((context) async {
        result = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            actions: [
              TextButton(
                onPressed: () {
                  popDialog(dialogContext, 'first');
                  popDialog(dialogContext, 'second');
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      }),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, 'first');
  });

  testWidgets('a normal single close still works', (tester) async {
    await tester.pumpWidget(
      app(
        (context) => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Dialog'),
            actions: [
              TextButton(
                onPressed: () => popDialog(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Dialog'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
}
