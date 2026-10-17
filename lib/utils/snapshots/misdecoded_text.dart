import 'dart:convert';

/// Undoes UTF-8 that was read as Latin-1, and leaves everything else alone.
///
/// Snapshots used to be turned into text a byte at a time
/// (`String.fromCharCodes`), so every character past ASCII came out as two to
/// four Latin-1 ones: "—" as "â" and two control characters, "é" as "Ã©".
/// Those names were then stored as they came out.
///
/// Text of that kind is exactly the Latin-1 encoding of valid UTF-8, so it is
/// re-read as UTF-8. Text that is not - anything with a character past
/// U+00FF, a lone "é" that no UTF-8 sequence produces, plain ASCII - is
/// returned unchanged. That makes it safe on a name that was never damaged,
/// and safe to run twice.
///
/// The one text it would change wrongly is a genuine Latin-1 name that also
/// happens to spell valid UTF-8, such as "Ã©" typed on purpose, which is far
/// rarer than the damage it undoes.
String repairMisdecodedUtf8(String text) {
  var pastAscii = false;

  for (final unit in text.codeUnits) {
    if (unit > 0xFF) {
      return text;
    }

    if (unit > 0x7F) {
      pastAscii = true;
    }
  }

  if (!pastAscii) {
    return text;
  }

  try {
    return utf8.decode(latin1.encode(text));
  } on FormatException {
    return text;
  }
}
