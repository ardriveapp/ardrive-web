/// Tells the browser that the text field being typed in holds a secret that
/// is not a password: no spell check, no autocomplete, no capitalising.
///
/// Flutter's web engine sets autocomplete and autocorrect but never
/// `spellcheck`, so Chrome's spell checker reads a textarea as you type,
/// and with enhanced spell check sends it to Google. Off the web it does
/// nothing.
library;

export 'secret_text_field_stub.dart'
    if (dart.library.html) 'secret_text_field_web.dart';
