import 'dart:async';

import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

import 'sandboxed_iframe_stub.dart'
    if (dart.library.html) 'sandboxed_iframe_web.dart';

/// The only way ArDrive will let a transaction render *itself*.
///
/// Everything ArDrive shows inline it has decoded first: an image through
/// `Image.memory`, a PDF rasterised to page images, text through a `Text`
/// widget. Content that a browser would *execute* - HTML, SVG, a manifest
/// opened as a site - is never decoded here at all. It is handed to the
/// gateway's per-transaction sandbox origin
/// (`{base32(txId)}.{gateway}`, see `arweave_sandbox_url.dart`), either in a new
/// tab or in an `<iframe sandbox>` with no `allow-same-origin`.
///
/// The invariant this widget exists to keep
/// (`docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3): bytes fetched from an arbitrary
/// transaction id never become script-capable content on the `app.ardrive.io`
/// origin, because a recipient's access key can be sitting in this origin's
/// `sessionStorage`. Note what this widget is *not* given: it takes a URL, not
/// bytes. There is no code path from a fetched byte to this widget, which is
/// what makes `srcdoc`, blob-URL HTML and `innerHtml` impossible here rather
/// than merely unused.
class SandboxedTransactionView extends StatefulWidget {
  const SandboxedTransactionView({
    super.key,
    required this.url,
    this.openLabel,
    this.height = 320,
  });

  /// The gateway sandbox URL to open. Built by `arweaveSandboxUrl`; never a
  /// blob, never a data URI, never anything on this origin.
  final String url;

  /// Overrides the button's copy for callers where "sandboxed" is not the word
  /// a reader needs (an unrecognised file, say, where the honest offer is just
  /// to open it on the gateway).
  final String? openLabel;

  /// The height the inline frame gets when it is shown.
  final double height;

  @override
  State<SandboxedTransactionView> createState() =>
      _SandboxedTransactionViewState();
}

class _SandboxedTransactionViewState extends State<SandboxedTransactionView> {
  /// Registered once, on first reveal: registering per build would leak a view
  /// factory on every frame.
  String? _viewType;

  bool _isShowingInline = false;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final viewType = _viewType;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ArDriveButton(
          maxWidth: double.infinity,
          style: ArDriveButtonStyle.secondary,
          onPressed: _open,
          text: widget.openLabel ??
              appLocalizationsOf(context).rawTransactionOpenSandboxed,
        ),
        if (sandboxedIframeIsSupported) ...[
          const SizedBox(height: 8),
          ArDriveButton(
            style: ArDriveButtonStyle.tertiary,
            onPressed: _toggleInline,
            text: _isShowingInline
                ? appLocalizationsOf(context).rawTransactionHideSandboxedFrame
                : appLocalizationsOf(context).rawTransactionShowSandboxedFrame,
          ),
        ],
        if (_isShowingInline && viewType != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                border: Border.all(color: colors.themeBorderDefault),
                borderRadius: BorderRadius.circular(4),
              ),
              child: HtmlElementView(viewType: viewType),
            ),
          ),
        ],
      ],
    );
  }

  void _toggleInline() {
    setState(() {
      _isShowingInline = !_isShowingInline;
      _viewType ??= registerSandboxedIframe(widget.url);
    });
  }

  /// Fire and forget, like every other outbound link in the app.
  ///
  /// A refused scheme is handled inside [openUrl] - it will not launch
  /// anything that is not http(s), and it logs the refusal itself. A second
  /// `try`/`catch` here would only log the same failure twice and would put
  /// this one call site on a different contract from the other thirty.
  void _open() {
    unawaited(openUrl(url: widget.url, webOnlyWindowName: '_blank'));
  }
}
