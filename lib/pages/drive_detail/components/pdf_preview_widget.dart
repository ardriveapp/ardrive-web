import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// Builds the inline viewer for [bytes], calling [onRenderFailed] if it cannot.
///
/// Exists so the degradation path can be tested without a PDF rasteriser -
/// and, later, so a different rasteriser can be dropped in without touching
/// this card.
typedef PdfViewerBuilder = Widget Function(
  BuildContext context,
  Uint8List bytes,
  VoidCallback onRenderFailed,
);

/// A PDF, drawn here as images rather than handed to the browser.
///
/// [pdfBytes] is the file's plaintext, already fetched (and, for a private
/// file, already decrypted) by [FsEntryPreviewCubit]. It goes to a rasteriser
/// that turns pages into images, which are painted as ordinary Flutter widgets
/// - the same posture as the image preview, and the reason a PDF's embedded
/// JavaScript never runs: nothing here is DOM, so there is nothing for a script
/// to be script *on*. A blob URL in an `<iframe>`/`<embed>`/`<object>` would
/// put bytes from an untrusted transaction on `app.ardrive.io` as
/// script-capable content, which `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3
/// forbids and which is load-bearing because a recipient's access key can be
/// sitting in this origin's `sessionStorage`.
///
/// When there are no bytes, or the rasteriser cannot render them, this degrades
/// to what this widget used to be: an offer to open the file's *public* gateway
/// URL in a new tab, where the browser's own viewer renders it on the gateway's
/// origin. A private file has no such URL, so it degrades to a plain
/// unavailable card instead.
class PdfPreviewWidget extends StatefulWidget {
  const PdfPreviewWidget({
    super.key,
    required this.filename,
    required this.previewUrl,
    this.pdfBytes,
    this.canOpenOnGateway = false,
    this.viewerBuilder,
  });

  final String filename;

  /// The gateway URL for the file's public bytes. Only meaningful when
  /// [canOpenOnGateway] is set.
  final String previewUrl;

  /// The file's plaintext, or `null` when it could not be had.
  final Uint8List? pdfBytes;

  /// Whether [previewUrl] points at bytes a browser could render itself, which
  /// is true only for a public file.
  final bool canOpenOnGateway;

  /// Injectable for tests; otherwise the real rasteriser.
  final PdfViewerBuilder? viewerBuilder;

  @override
  State<PdfPreviewWidget> createState() => _PdfPreviewWidgetState();
}

class _PdfPreviewWidgetState extends State<PdfPreviewWidget> {
  bool _renderFailed = false;

  @override
  void didUpdateWidget(covariant PdfPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // New bytes deserve a new attempt; the same bytes do not.
    if (!identical(oldWidget.pdfBytes, widget.pdfBytes)) {
      setState(() => _renderFailed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.pdfBytes;

    if (bytes == null || _renderFailed) {
      return _PdfFallbackCard(
        filename: widget.filename,
        onOpen: widget.canOpenOnGateway ? _open : null,
      );
    }

    final buildViewer = widget.viewerBuilder ?? _buildViewer;

    return buildViewer(context, bytes, _onRenderFailed);
  }

  Widget _buildViewer(
    BuildContext context,
    Uint8List bytes,
    VoidCallback onRenderFailed,
  ) =>
      InlinePdfView(
        bytes: bytes,
        onRenderFailed: onRenderFailed,
        onOpen: widget.canOpenOnGateway ? _open : null,
      );

  void _onRenderFailed() {
    if (!mounted || _renderFailed) {
      return;
    }

    setState(() => _renderFailed = true);
  }

  /// Fire and forget: [openUrl] never throws and logs its own failures, so a
  /// second `try`/`catch` here would report the same one twice.
  void _open() {
    unawaited(openUrl(url: widget.previewUrl, webOnlyWindowName: '_blank'));
  }
}

/// The rasterised pages, one at a time, with a bar to move between them.
///
/// Every page arrives as an image: [PdfView] renders through pdf.js on the web
/// and the platform's own renderer elsewhere, and hands back pixels. Scripting
/// is off - pdfx never asks pdf.js to turn it on, and pdf.js leaves it off by
/// default - so nothing inside the document executes.
class InlinePdfView extends StatefulWidget {
  const InlinePdfView({
    super.key,
    required this.bytes,
    required this.onRenderFailed,
    this.onOpen,
  });

  final Uint8List bytes;

  /// Called when the document cannot be opened or rendered at all, so the card
  /// around this can offer something that works instead.
  final VoidCallback onRenderFailed;

  /// Opens the file outside the app, when there is a public URL to open.
  final VoidCallback? onOpen;

  @override
  State<InlinePdfView> createState() => _InlinePdfViewState();
}

class _InlinePdfViewState extends State<InlinePdfView> {
  late PdfController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfController(document: _openDocument(widget.bytes));
  }

  @override
  void didUpdateWidget(covariant InlinePdfView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.bytes, widget.bytes)) {
      _controller.loadDocument(_openDocument(widget.bytes));
    }
  }

  @override
  void dispose() {
    final document = _controller.document;

    _controller.dispose();

    // The controller only owns the page controller, so the document - and the
    // decoded pages behind it - is released here rather than being left to live
    // as long as the tab.
    document.then((d) => d.close()).catchError((Object _) {});

    super.dispose();
  }

  /// The bytes, straight into the rasteriser.
  ///
  /// No blob URL and no temp file: [PdfDocument.openData] takes the plaintext
  /// in memory, which is the only place a private file's plaintext may exist.
  ///
  /// The platform check is done here rather than left to pdfx, whose own check
  /// throws from an unawaited future - a platform that cannot rasterise should
  /// degrade to the fallback card, not to an unhandled error.
  Future<PdfDocument> _openDocument(Uint8List bytes) async {
    if (!await hasPdfSupport()) {
      throw PlatformNotSupportedException();
    }

    return PdfDocument.openData(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Column(
      children: [
        Expanded(
          child: PdfView(
            controller: _controller,
            backgroundDecoration: BoxDecoration(color: colors.themeBgSubtle),
            onDocumentError: (error) {
              logger.d('Could not render a PDF preview inline: $error');
              widget.onRenderFailed();
            },
            builders: PdfViewBuilders<DefaultBuilderOptions>(
              options: const DefaultBuilderOptions(),
              documentLoaderBuilder: (_) => const Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(),
                ),
              ),
              pageLoaderBuilder: (_) => const Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(),
                ),
              ),
              // The card around this one takes over on an error, so this frame
              // shows nothing rather than a raw exception.
              errorBuilder: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ),
        _buildBar(context),
      ],
    );
  }

  Widget _buildBar(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Container(
      color: colors.themeBgCanvas,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: PdfPageNumber(
        controller: _controller,
        builder: (context, loadingState, page, pagesCount) {
          if (loadingState != PdfLoadingState.success ||
              pagesCount == null ||
              pagesCount == 0) {
            return const SizedBox(height: 40);
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: page > 1 ? _previousPage : null,
                icon: const Icon(Icons.arrow_back_ios_outlined, size: 16),
              ),
              Text(
                appLocalizationsOf(context)
                    .previewPdfPageIndicator(page, pagesCount),
                style: ArDriveTypography.body.captionRegular(
                  color: colors.themeFgSubtle,
                ),
              ),
              IconButton(
                onPressed: page < pagesCount ? _nextPage : null,
                icon: const Icon(Icons.arrow_forward_ios_outlined, size: 16),
              ),
              if (widget.onOpen != null)
                IconButton(
                  tooltip: appLocalizationsOf(context).previewPdfOpen,
                  onPressed: widget.onOpen,
                  icon: ArDriveIcons.newWindow(
                    size: 16,
                    color: colors.themeFgSubtle,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _previousPage() => _controller.previousPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );

  void _nextPage() => _controller.nextPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
}

/// What is shown when there is nothing to rasterise.
///
/// With [onOpen] this is the card this widget used to be, unchanged: the
/// browser opens the file's own gateway URL in a new tab and renders it there,
/// on an origin that is not this one. Without it - a private file, whose
/// ciphertext no browser can render - there is nothing to offer but the truth.
class _PdfFallbackCard extends StatelessWidget {
  const _PdfFallbackCard({
    required this.filename,
    this.onOpen,
  });

  final String filename;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            getIconForContentType('application/pdf', size: 40),
            const SizedBox(height: 12),
            Text(
              filename,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: ArDriveTypography.body.bodyBold(
                color: colors.themeFgDefault,
              ),
            ),
            const SizedBox(height: 16),
            if (onOpen != null) ...[
              ArDriveButton(
                icon: ArDriveIcons.newWindow(size: 20, color: Colors.white),
                text: appLocalizationsOf(context).previewPdfOpen,
                onPressed: onOpen!,
              ),
              const SizedBox(height: 8),
              Text(
                appLocalizationsOf(context).previewPdfOpensInNewTab,
                textAlign: TextAlign.center,
                style: ArDriveTypography.body.captionRegular(
                  color: colors.themeFgSubtle,
                ),
              ),
            ] else
              Text(
                appLocalizationsOf(context).previewUnavailable,
                textAlign: TextAlign.center,
                style: ArDriveTypography.body.captionRegular(
                  color: colors.themeFgSubtle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
