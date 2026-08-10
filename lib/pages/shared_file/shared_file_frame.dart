import 'dart:math';

import 'package:ardrive/components/app_version_widget.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The one column the recipient landing page lives in, at every state and
/// every width.
///
/// Mobile web is where most shared links are opened, so this is a single
/// scrolling column rather than a desktop/mobile fork: the card never exceeds
/// [maxContentWidth], and on a short screen the whole page scrolls instead of
/// pushing the key field or the download button off screen.
class SharedFileFrame extends StatelessWidget {
  const SharedFileFrame({super.key, required this.child});

  /// Wide enough for a full width [ArDriveButton] (368) plus the card padding,
  /// and narrow enough to stay a readable single column on a desktop monitor.
  static const double maxContentWidth = 400;

  static const double _verticalPadding = 24;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;

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
                    constraints: const BoxConstraints(
                      maxWidth: maxContentWidth,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTrustStrip(context),
                        const SizedBox(height: 24),
                        ArDriveCard(
                          backgroundColor: theme.colors.themeBgSurface,
                          elevation: 2,
                          contentPadding: const EdgeInsets.all(16),
                          content: child,
                        ),
                        const SizedBox(height: 16),
                        ArDriveButton(
                          style: ArDriveButtonStyle.tertiary,
                          onPressed: () =>
                              openUrl(url: Resources.ardrivePublicSiteLink),
                          text: appLocalizationsOf(context).whatIsArDrive,
                        ),
                        const SizedBox(height: 8),
                        AppVersionWidget(color: theme.colors.themeFgSubtle),
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
        ArDriveImage(
          image: AssetImage(
            // TODO: replace with ArDriveTheme .isLight method
            theme.name == 'light'
                ? Resources.images.brand.blackLogo2
                : Resources.images.brand.whiteLogo2,
          ),
          height: 55,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 8),
        Text(
          appLocalizationsOf(context).sharedFilePermanentFileSharing,
          textAlign: TextAlign.center,
          style: ArDriveTypography.body.captionRegular(
            color: theme.colors.themeFgSubtle,
          ),
        ),
      ],
    );
  }
}
