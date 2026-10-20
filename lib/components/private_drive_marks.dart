import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The lock that says a drive is private, for the places that show a drive's
/// name without room for a word.
///
/// The drives list marks private drives with this same icon. It carries a
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
      child: Tooltip(
        message: label,
        child:
            ArDriveIcons.privateDrive(size: size, color: colorTokens.textMid),
      ),
    );
  }
}

/// The line the upload dialogs show for a private drive, so the choice made
/// when the drive was created is visibly still in force.
class EncryptedUploadNote extends StatelessWidget {
  const EncryptedUploadNote({super.key});

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Row(
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
    );
  }
}
