import 'package:flutter/material.dart';

// A date input that opens a calendar instead of asking people to type. The value stays the plain
// text the API already takes ('YYYY-MM-DD', or empty for "no date") and lives in the controller, so
// callers read `controller.text` exactly as they would from a TextField.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.controller,
    required this.label,
    this.notBefore,
    this.border,
  });

  final TextEditingController controller;
  final String label;

  // Another date field whose value, when set, is the earliest date this one can pick (an end date
  // cannot precede the start date). The backend enforces it too.
  final TextEditingController? notBefore;
  final InputBorder? border;

  static String format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  // Parses 'YYYY-MM-DD'; anything else (including empty) is "no date".
  static DateTime? parse(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final floor = notBefore == null ? null : parse(notBefore!.text);
    final first = floor ?? DateTime(2000);
    var initial = parse(controller.text) ?? floor ?? DateTime.now();
    if (initial.isBefore(first)) initial = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(2100),
    );
    if (picked != null) controller.text = format(picked);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        readOnly: true,
        onTap: () => _pick(context),
        decoration: InputDecoration(
          labelText: label,
          border: border,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear $label',
                  onPressed: controller.clear,
                ),
              IconButton(
                icon: const Icon(Icons.calendar_today, size: 18),
                tooltip: 'Pick $label',
                onPressed: () => _pick(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
