import 'package:cloud_functions/cloud_functions.dart';
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

// A message a person can act on for a failed function call. Our own refusals (permission-denied,
// failed-precondition, invalid-argument and so on) already carry a readable sentence from the server and
// are shown as they are. The transport failures have no useful text, for example an offline phone shows
// only "internal [0]", so those become one plain sentence.
String friendlyError(FirebaseFunctionsException e) {
  const transportCodes = {'internal', 'unavailable', 'deadline-exceeded', 'unknown', 'cancelled'};
  final message = (e.message ?? '').trim();
  final hasRealMessage = message.isNotEmpty && !RegExp(r'^(internal|unavailable|unknown|cancelled|deadline)\b.*$', caseSensitive: false).hasMatch(message);
  if (transportCodes.contains(e.code) && !hasRealMessage) {
    return "Couldn't reach the server. Check your connection and try again.";
  }
  return message.isEmpty ? e.code : message;
}
