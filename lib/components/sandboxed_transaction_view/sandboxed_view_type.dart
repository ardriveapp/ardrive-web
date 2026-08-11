int _registrations = 0;

/// The name a sandboxed transaction frame registers its view factory under.
///
/// Unique **by construction, not by clock**. The first version of this built
/// the name from `DateTime.now().microsecondsSinceEpoch`, which on the web is
/// always a multiple of 1000: `DateTime.now()` has millisecond resolution
/// there, so two frames created inside the same millisecond - a page that
/// reveals two transactions, a rebuild that reveals one twice - asked
/// `registerViewFactory` for the *same* view type. A duplicate registration is
/// either rejected or overwrites the first factory, and then one transaction
/// renders the other one's URL, inside a frame whose whole purpose is to keep
/// those two apart.
///
/// The counter is what makes the name unique; the timestamp is kept only
/// because it makes a view type readable in a DOM inspector. A monotonic
/// counter is enough on its own: the platform view registry lives for exactly
/// as long as the document does, so a name only has to be unique within one
/// page session, and a reload starts both the registry and this counter over.
///
/// Lives outside the conditional web/stub import so that it can be tested
/// where `dart:html` cannot be loaded.
String nextSandboxedViewType() => 'sandboxed-transaction-'
    '${DateTime.now().microsecondsSinceEpoch}-'
    '${_registrations++}';
