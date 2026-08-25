import 'package:ardrive/components/sandboxed_transaction_view/sandboxed_transaction_view.dart';
import 'package:ardrive/pages/drive_detail/components/document_preview_widget.dart';
import 'package:ardrive/pages/drive_detail/components/pdf_preview_widget.dart';
// `VideoPlayerWidget` and `AudioPlayerWidget` are part of the drive detail
// library; `show` keeps the rest of that very large surface out of this file.
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart'
    show AudioPlayerWidget, VideoPlayerWidget;
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_content.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Renders a transaction the one way [RawTransactionPresentation] permits.
///
/// The branch is chosen upstream, in [decidePresentation], and this widget does
/// not second-guess it. That separation is the point: the decision is made once,
/// against the bytes, in a file with no widgets in it - and every widget below
/// is either a decoder that produces Flutter widgets ([Image.memory],
/// [PdfPreviewWidget], [DocumentPreviewWidget]) or a pointer at somebody else's
/// origin ([SandboxedTransactionView], the media players' URLs).
///
/// What is *not* here is the whole invariant: no `srcdoc`, no `innerHtml`, no
/// blob URL on this origin, no `<iframe>`/`<embed>`/`<object>` fed transaction
/// bytes. HTML and SVG reach this file as a `String` and leave it as a `Text`
/// widget (`docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3).
class RawTransactionPreview extends StatelessWidget {
  const RawTransactionPreview({
    super.key,
    required this.state,
    this.pdfViewerBuilder,
    this.mediaBuilder,
  });

  final RawTransactionReady state;

  /// Injectable for tests; otherwise the real rasteriser, which needs pdf.js or
  /// a platform renderer and has neither in a VM test.
  final PdfViewerBuilder? pdfViewerBuilder;

  /// Injectable for tests; otherwise the app's own players, which reach for a
  /// video/audio plugin that a VM test does not have.
  final Widget Function(BuildContext context, String url, String contentType)?
      mediaBuilder;

  /// The height the inline viewers are given on the recipient card.
  static const double maxPreviewHeight = 360;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.presentation.claimIsContradicted) ...[
          _RawTransactionNotice(
            icon: ArDriveIcons.triangle(size: 16, color: colors.themeWarningFg),
            message: appLocalizationsOf(context).rawTransactionTypeMismatch,
            color: colors.themeWarningFg,
          ),
          const SizedBox(height: 12),
        ],
        if (state.presentation.renderer ==
            RawTransactionRenderer.sandboxed) ...[
          _RawTransactionNotice(
            icon: ArDriveIcons.info(size: 16, color: colors.themeFgSubtle),
            message: appLocalizationsOf(context).rawTransactionSandboxedNotice,
            color: colors.themeFgSubtle,
          ),
          const SizedBox(height: 12),
        ],
        _buildBody(context),
        if (state.presentation.offersSandboxedOpen) ...[
          const SizedBox(height: 12),
          SandboxedTransactionView(
            url: state.sandboxUrl,
            // "Sandboxed" is the word that matters for content a browser would
            // execute. For a file we simply could not read, the honest offer is
            // the plainer one.
            openLabel:
                state.presentation.renderer == RawTransactionRenderer.sandboxed
                    ? null
                    : appLocalizationsOf(context).rawTransactionOpenOnGateway,
          ),
        ],
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final bytes = state.bytes;
    final text = state.text;
    final filename =
        state.name ?? appLocalizationsOf(context).rawTransactionGenericTitle;

    switch (state.presentation.renderer) {
      case RawTransactionRenderer.image:
        if (bytes == null) {
          return _message(
            context,
            appLocalizationsOf(context).previewUnavailable,
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: maxPreviewHeight),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            // The last safety net under the sniffer: bytes that opened like a
            // PNG and are not one become a message, never a crash.
            errorBuilder: (context, error, stackTrace) => _message(
              context,
              appLocalizationsOf(context).previewUnavailable,
            ),
          ),
        );

      case RawTransactionRenderer.pdf:
        if (bytes == null) {
          return _message(
            context,
            appLocalizationsOf(context).previewUnavailable,
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: maxPreviewHeight,
            minHeight: 120,
          ),
          child: PdfPreviewWidget(
            filename: filename,
            // Public bytes, so the browser's own viewer on the gateway's
            // per-transaction origin is a real fallback when the rasteriser
            // cannot cope.
            previewUrl: state.sandboxUrl,
            pdfBytes: bytes,
            canOpenOnGateway: true,
            viewerBuilder: pdfViewerBuilder,
          ),
        );

      case RawTransactionRenderer.markdown:
        if (text == null) {
          return _message(
            context,
            appLocalizationsOf(context).previewUnavailable,
          );
        }

        return _buildDocument(context, filename, text, 'text/markdown');

      case RawTransactionRenderer.text:
        if (text == null) {
          return _message(
            context,
            appLocalizationsOf(context).previewUnavailable,
          );
        }

        return _buildDocument(
          context,
          filename,
          text,
          state.presentation.contentType ?? 'text/plain',
        );

      case RawTransactionRenderer.sandboxed:
        if (text == null) {
          return const SizedBox.shrink();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocalizationsOf(context).rawTransactionSourceHeading,
              style: ArDriveTypography.body.captionBold(
                color: colors.themeFgSubtle,
              ),
            ),
            const SizedBox(height: 8),
            // `text/plain`, deliberately, whatever the transaction said it was.
            // `DocumentPreviewWidget` renders anything that is not markdown as
            // a plain `Text`, and naming the type here means a later change to
            // that widget cannot quietly start interpreting these bytes.
            _buildDocument(context, filename, text, 'text/plain'),
          ],
        );

      case RawTransactionRenderer.media:
        final contentType = state.presentation.contentType ?? '';
        final builder = mediaBuilder;

        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: maxPreviewHeight,
            minHeight: 120,
          ),
          // Both players take a URL, and the URL is the gateway's
          // per-transaction origin. Nothing about these bytes is decoded here,
          // and a media element cannot execute what it is given.
          child: builder != null
              ? builder(context, state.sandboxUrl, contentType)
              : contentType.startsWith('audio/')
                  ? AudioPlayerWidget(
                      filename: filename,
                      audioUrl: state.sandboxUrl,
                      isSharePage: true,
                    )
                  : VideoPlayerWidget(
                      filename: filename,
                      videoUrl: state.sandboxUrl,
                      isSharePage: true,
                    ),
        );

      case RawTransactionRenderer.downloadOnly:
        if (state.isOversized) {
          return _message(
            context,
            appLocalizationsOf(context)
                .filePreviewTooLarge(filesize(rawTransactionInlineMaxBytes)),
          );
        }

        return _message(
          context,
          appLocalizationsOf(context).rawTransactionUnknownType,
        );
    }
  }

  Widget _buildDocument(
    BuildContext context,
    String filename,
    String text,
    String contentType,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: maxPreviewHeight,
        minHeight: 120,
      ),
      child: DocumentPreviewWidget(
        filename: filename,
        content: text,
        contentType: contentType,
        isSharePage: true,
      ),
    );
  }

  Widget _message(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: ArDriveTypography.body.captionRegular(
          color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
        ),
      ),
    );
  }
}

/// One line of explanation with an icon, the shape the identity card already
/// uses for its mismatch warning.
class _RawTransactionNotice extends StatelessWidget {
  const _RawTransactionNotice({
    required this.icon,
    required this.message,
    required this.color,
  });

  final Widget icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: ArDriveTypography.body.captionRegular(color: color),
          ),
        ),
      ],
    );
  }
}
