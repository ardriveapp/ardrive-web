// Truncate a string by adding ... in the middle
String truncateString(
  String text, {
  required int offsetStart,
  required int offsetEnd,
}) {
  final textLength = text.length;
  if (textLength <= offsetStart + offsetEnd) {
    throw Exception(
      'The text length must be longer than the sum of the offsets',
    );
  }

  final beginning = text.substring(0, offsetStart);
  final end = text.substring(textLength - offsetEnd);
  return '$beginning...$end';
}

/// The one short form of an ID or a wallet address the app shows: its first
/// six characters, `...` and its last four (`abc123...xyz9`), the form
/// `packages/ardrive_ui/README.md` documents. Enough to tell two apart, and
/// the same everywhere, so one address reads the same wherever it appears.
/// One no longer than that form is returned whole.
String shortenId(String id) =>
    id.length <= 13 ? id : truncateString(id, offsetStart: 6, offsetEnd: 4);
