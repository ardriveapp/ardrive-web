// Non-web platforms have no iframe and no browser origin to isolate, so there
// is nothing to sandbox: [SandboxedTransactionView] falls back to opening the
// gateway's own sandbox URL in the platform browser, which is a separate
// process with a separate origin either way.

/// Whether this platform can show an isolated frame in the page.
///
/// A getter rather than a `const`, so the platform that does not have frames
/// does not turn every caller's branch into a compile-time dead one.
bool get sandboxedIframeIsSupported => false;

/// Registers nothing. Always returns `null`, so callers render the
/// open-in-a-new-tab affordance instead.
String? registerSandboxedIframe(String url) => null;
