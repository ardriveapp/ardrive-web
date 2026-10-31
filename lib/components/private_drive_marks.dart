import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The lock that says a drive is private, for the places that show a drive's
/// name without room for a word.
///
/// The drives list puts it after a private drive's name. It carries a
/// label as well as a tooltip, because an icon alone is silent to a screen
/// reader.
class PrivateDriveLock extends StatelessWidget {
  const PrivateDriveLock({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    final label = appLocalizationsOf(context).privateDriveLabel;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      // ArDriveTooltip, not Material's: in a row that starts selecting on a
      // long press, it leaves the long press to the row.
      child: ArDriveTooltip(
        message: label,
        child:
            ArDriveIcons.privateDrive(size: size, color: colorTokens.textMid),
      ),
    );
  }
}

/// The line the upload dialogs show for a private drive, so the choice made
/// when the drive was created is visibly still in force.
///
/// Draws nothing for a public drive, so each dialog layout can place it
/// without its own condition.
class EncryptedUploadNote extends StatelessWidget {
  const EncryptedUploadNote({super.key, required this.isPrivate});

  final bool isPrivate;

  @override
  Widget build(BuildContext context) {
    if (!isPrivate) {
      return const SizedBox.shrink();
    }

    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArDriveIcons.privateDrive(size: 16, color: colorTokens.textMid),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              appLocalizationsOf(context).uploadEncryptedNote,
              style: typography.paragraphNormal(
                color: colorTokens.textMid,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
