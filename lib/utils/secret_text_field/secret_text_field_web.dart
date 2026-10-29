// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

/// Marks the element the engine is typing into, which is the focused one.
/// The engine makes a new element each time a field takes focus, so this is
/// called on focus and on each change.
void markFocusedFieldSecret() {
  final element = html.document.activeElement;
  if (element is! html.TextAreaElement && element is! html.InputElement) {
    return;
  }
  element!
    ..spellcheck = false
    ..setAttribute('autocomplete', 'off')
    ..setAttribute('autocapitalize', 'off')
    ..setAttribute('autocorrect', 'off');
}
