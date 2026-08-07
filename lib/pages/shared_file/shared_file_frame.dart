import 'dart:math';

import 'package:ardrive/components/app_version_widget.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/shared_file/shared_file_colors.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The chrome the recipient landing page lives in, at every state and every
/// width.
///
/// Mobile web is where most shared links are opened, so the default is a single
/// scrolling column: the card never exceeds [maxContentWidth], and on a short
/// screen the whole page scrolls instead of pushing the key field or the
/// download button off screen.
///
/// One state asks for more room. The ready card hosts the preview, and a 400px
/// preview on a monitor is a worse answer than the one this page replaced, so
/// the page hands that state [maxWideContentWidth] on a desktop screen. Every
/// other state stays narrow on purpose - a key entry form stretched across
/// 1200px is not an improvement on one that is 400px wide.
class SharedFileFrame extends StatelessWidget {
  const SharedFileFrame({
    super.key,
    required this.child,
    this.maxWidth = maxContentWidth,
  });

  /// Wide enough for a full width [ArDriveButton] (368) plus the card padding,
  /// and narrow enough to stay a readable single column on a desktop monitor.
  static const double maxContentWidth = 400;

  /// The ready card's width on a desktop screen: an actions column the same
  /// width as the phone's, a gutter, and a preview pane with real room left
  /// over. See `SharedFileReadyView` for the arithmetic.
  static const double maxWideContentWidth = 1040;

  static const double _verticalPadding = 24;

  final Widget child;

  /// How wide the card is allowed to get. Defaults to the single column.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;
    final isWide = maxWidth > maxContentWidth;

    return Container(
      color: theme.tableTheme.backgroundColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: _verticalPadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // Centers the card on a tall screen and lets it scroll on a
                  // short one, which is the whole trick to a landing page that
                  // survives a phone in landscape.
                  minHeight: constraints.hasBoundedHeight
                      ? max(0.0, constraints.maxHeight - _verticalPadding * 2)
                      : 0.0,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTrustStrip(context),
                        const SizedBox(height: 24),
                        ArDriveCard(
                          backgroundColor: theme.colors.themeBgSurface,
                          elevation: 2,
                          contentPadding: EdgeInsets.all(isWide ? 24 : 16),
                          content: child,
                        ),
                        const SizedBox(height: 16),
                        // Centred rather than stretched: on the wide card a
                        // full width text button would be a 1040px underline.
                        Center(
                          child: ArDriveButton(
                            style: ArDriveButtonStyle.tertiary,
                            onPressed: () =>
                                openUrl(url: Resources.ardrivePublicSiteLink),
                            text: appLocalizationsOf(context).whatIsArDrive,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AppVersionWidget(
                          color: SharedFileColors.subtle(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrustStrip(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The wordmark says the same thing as the line under it, so a screen
        // reader is told it once rather than twice.
        ExcludeSemantics(
          child: ArDriveImage(
            image: AssetImage(
              // TODO: replace with ArDriveTheme .isLight method
              theme.name == 'light'
                  ? Resources.images.brand.blackLogo2
                  : Resources.images.brand.whiteLogo2,
            ),
            height: 55,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          appLocalizationsOf(context).sharedFilePermanentFileSharing,
          textAlign: TextAlign.center,
          style: ArDriveTypography.body.captionRegular(
            color: SharedFileColors.subtle(context),
          ),
        ),
      ],
    );
  }
}
