import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/components/settings_popover.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The sign-in card: the standard dialog's surface, red band, radius, shadow
/// and close button, with the roomier padding of a page's main card.
///
/// It used to be its own container copied from the dialog, without the
/// dialog's shadow and with a smaller close button, so sign-in looked like a
/// near miss of every other dialog.
class ArDriveLoginModal extends StatelessWidget {
  const ArDriveLoginModal({
    super.key,
    required this.content,
    this.width,
    this.hasCloseButton = true,
    this.hasSettingsButton = false,
    this.onClose,
    this.padding,
  });

  final Widget content;
  final double? width;
  final bool hasCloseButton;
  final bool hasSettingsButton;
  final Function()? onClose;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final deviceWidth = MediaQuery.sizeOf(context).width;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final isPhone = deviceWidth < TABLET;
    final hasTopControl = hasCloseButton || hasSettingsButton;

    final side = isPhone ? ArDriveSpacing.lg : ArDriveSpacing.xxl;
    final contentPadding = EdgeInsets.fromLTRB(
      side,
      hasTopControl ? 0 : ArDriveSpacing.lg,
      side,
      isPhone ? ArDriveSpacing.xl : ArDriveSpacing.xxl,
    );

    return ArDriveModalNew(
      constraints: BoxConstraints(
        minHeight: 100,
        maxWidth: width ?? modalStandardMaxWidthSize,
        minWidth: 250,
      ),
      contentPadding: EdgeInsets.zero,
      // Full width with the content centred, as the card always laid it out:
      // the dialog's own column starts its children at the left.
      content: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasTopControl)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(ArDriveSpacing.md),
                  child: hasCloseButton
                      ? ArDriveIconButton(
                          icon: ArDriveIcon(
                            icon: ArDriveIconsData.x,
                            size: 24,
                            color: colorTokens.iconMid,
                          ),
                          tooltip: appLocalizationsOf(context).close,
                          onPressed: onClose ?? () => Navigator.pop(context),
                        )
                      : SettingsSubmenu(
                          child: ArDriveClickArea(
                            tooltip:
                                appLocalizationsOf(context).advancedSettings,
                            child: Icon(
                              Icons.settings,
                              size: 24,
                              color: colorTokens.iconMid,
                            ),
                          ),
                        ),
                ),
              ),
            Padding(
              padding: padding ?? contentPadding,
              child: content,
            ),
          ],
        ),
      ),
    );
  }
}
