// Reading a number from a text box without ever guessing. An empty box means "no value" (clear it),
// a number inside the allowed range is accepted, and anything else is an error the user is shown;
// it is never quietly turned into "no value". (`num.tryParse('abc')` is null, which used to be sent
// to the server as "clear this", silently erasing a handicap or a wager pot.)
class ParsedNumber {
  const ParsedNumber.ok(this.value) : error = null;
  const ParsedNumber.error(this.error) : value = null;

  // The number, or null when the box was empty. Only meaningful when [ok].
  final num? value;
  final String? error;

  bool get ok => error == null;
}

ParsedNumber parseOptionalNumber(
  String text, {
  required num min,
  required num max,
  required String what,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const ParsedNumber.ok(null);
  final value = num.tryParse(trimmed);
  if (value == null || !value.isFinite || value < min || value > max) {
    return ParsedNumber.error('$what must be a number from $min to $max');
  }
  return ParsedNumber.ok(value);
}

// The same limits the backend enforces (functions/src/limits.ts); the server stays the authority,
// this only gives an immediate, readable message.
ParsedNumber parseHandicap(String text) =>
    parseOptionalNumber(text, min: -10, max: 54, what: 'Handicap');

ParsedNumber parseWagerPot(String text) =>
    parseOptionalNumber(text, min: 0, max: 100000, what: 'Wager pot');
