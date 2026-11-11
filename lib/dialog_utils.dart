import 'package:flutter/material.dart';

// Closes the dialog that [context] belongs to, once. A fast second tap on a dialog button lands
// while the dialog is still animating out; a plain Navigator.pop would then pop the page underneath
// it and leave a blank screen. A dialog that has already been popped is no longer the current route,
// so the extra tap is ignored.
void popDialog<T extends Object?>(BuildContext context, [T? result]) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isCurrent) return;
  Navigator.of(context).pop<T>(result);
}

// Shows a failed action's message at the bottom of the screen where it is seen at once. The inline
// error text sits at the end of a long section, which on a phone is usually off-screen, so a refused
// Delete or Remove looked like nothing had happened.
void showErrorMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 6),
      ),
    );
}
