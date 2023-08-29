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
