/// Whether [text], an error's `toString()`, tells a person nothing.
///
/// A release build is compiled with minified class names, so an exception
/// without its own `toString` prints as `Instance of 'minified:Xy'`, and an
/// `Equatable` one (whose `stringify` is off outside debug) as `minified:Xy`.
/// Neither belongs in front of a user, or in a message support is meant to
/// search for; the log keeps the error itself.
bool isOpaqueErrorText(String text) =>
    text.contains('minified:') || text.contains('Instance of ');
