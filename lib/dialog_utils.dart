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
