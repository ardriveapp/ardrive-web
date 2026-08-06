import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A PDF, handed to the browser instead of drawn here.
///
/// The bytes are never brought into the app: the button opens the file's own
/// gateway URL in a new tab, where the browser's PDF viewer renders it on the
/// *gateway's* origin. That is deliberate, and it is the whole design of this
/// widget — a PDF can carry JavaScript, so decoding one into a blob URL and
/// dropping it into an `<iframe>` or `<embed>` would put script-capable content
/// from an untrusted transaction on `app.ardrive.io`, which
/// `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3 forbids.
///
/// Only public bytes ever reach this widget. Rendering a *private* PDF inline
/// needs a Flutter-native renderer that decodes bytes into widgets — no DOM, no
/// origin — which is a dependency decision rather than a code change.
class PdfPreviewWidget extends StatelessWidget {
  const PdfPreviewWidget({
    super.key,
    required this.filename,
    required this.previewUrl,
  });

  final String filename;

  /// The gateway URL for the file's public bytes.
  final String previewUrl;

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
            ArDriveButton(
              icon: ArDriveIcons.newWindow(size: 20, color: Colors.white),
              text: appLocalizationsOf(context).previewPdfOpen,
              onPressed: () => _open(),
            ),
            const SizedBox(height: 8),
            Text(
              appLocalizationsOf(context).previewPdfOpensInNewTab,
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

  Future<void> _open() async {
    try {
      await openUrl(url: previewUrl, webOnlyWindowName: '_blank');
    } catch (e) {
      logger.e('Could not open a PDF preview in a new tab', e);
    }
  }
}
