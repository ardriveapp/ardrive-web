// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:ardrive/components/sandboxed_transaction_view/sandboxed_view_type.dart';

/// Whether this platform can show an isolated frame in the page.
bool get sandboxedIframeIsSupported => true;

/// Registers a platform view that renders [url] inside a sandboxed `<iframe>`,
/// and returns the view type to hand to `HtmlElementView`.
///
/// Two things make this safe to point at bytes an attacker chose, and both are
/// load-bearing:
///
/// * **`src`, never `srcdoc`.** The frame *navigates* to the gateway's
///   per-transaction sandbox origin (`{base32(txId)}.{gateway}`). Nothing from
///   the transaction is ever handed to this document - not through `srcdoc`,
///   not through a blob URL, not through `innerHtml` - so nothing from the
///   transaction is ever parsed on `app.ardrive.io`.
/// * **`sandbox` without `allow-same-origin`.** The frame is given a unique
///   opaque origin, so even the gateway origin it loaded from is not its own:
///   it cannot reach this page's `sessionStorage` (where a recipient's access
///   key can be sitting), `localStorage`, cookies, or DOM. `allow-scripts` is
///   granted because a web page that cannot run its own scripts is not the
///   page the sender published - and, without `allow-same-origin`, scripts have
///   nothing of ours to run against. `allow-top-navigation`, `allow-popups`,
///   `allow-modals` and `allow-forms` are all deliberately withheld, so the
///   frame cannot navigate the tab away, spawn a window, or raise a dialog that
///   would read as ArDrive's own.
///
/// `referrerpolicy=no-referrer` keeps the viewer's `/view/{txId}` URL out of the
/// gateway's and the content's logs.
String? registerSandboxedIframe(String url) {
  // One registration per call site rather than per build: the caller registers
  // once and holds the returned type, and a fresh type per URL keeps a second
  // transaction from inheriting the first one's factory. See
  // [nextSandboxedViewType] for why that freshness cannot come from the clock.
  final viewType = nextSandboxedViewType();

  // ignore: undefined_prefixed_name
  ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = html.IFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';

    iframe.setAttribute('sandbox', 'allow-scripts allow-downloads');
    iframe.setAttribute('referrerpolicy', 'no-referrer');

    return iframe;
  });

  return viewType;
}
