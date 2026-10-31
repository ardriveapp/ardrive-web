/// [text] with its last space made non-breaking, so a wrapped line never
/// leaves its last word alone on a line of its own.
///
/// For text drawn on screen only: a screen reader should get [text] as it is.
String keepLastWordsTogether(String text) {
  final last = text.lastIndexOf(' ');
  return last < 0
      ? text
      : '${text.substring(0, last)} ${text.substring(last + 1)}';
}
