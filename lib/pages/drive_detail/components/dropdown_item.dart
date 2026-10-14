import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

enum ArDriveArDriveDropdownItemTileIconAlignment {
  left,
  right,
}

class ArDriveDropdownItemTile extends StatelessWidget {
  final String name;
  final ArDriveIcon? icon;
  final bool isDisabled;
  final TextStyle? fontStyle;
  final ArDriveArDriveDropdownItemTileIconAlignment iconAlignment;
  final double? height;

  const ArDriveDropdownItemTile({
    super.key,
    required this.name,
    this.icon,
    this.isDisabled = false,
    this.fontStyle,
    this.iconAlignment = ArDriveArDriveDropdownItemTileIconAlignment.left,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0),
      child: SizedBox(
        // Scaled: the row is a fixed 48 at scale 1, and a label at text scale
        // 2 needs twice the line box. Without this the label is squeezed
        // instead of the row growing, and "Sync history" - the only door to
        // the history - reads as a cut-off word on a 320px phone.
        height: (height ?? 48) *
            MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            if (icon != null &&
                iconAlignment ==
                    ArDriveArDriveDropdownItemTileIconAlignment.left) ...[
              icon!.copyWith(
                color: isDisabled
                    ? ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentDisabled
                    : null,
              ),
              const SizedBox(width: 20),
            ],
            // Flexible, and allowed to ellipsize. The row is `MainAxisSize.max`
            // inside a menu whose width is the screen's on a phone, so a label
            // that insisted on its full width overflowed it: at 320px and text
            // scale 2.0, "Deep Resync" ran 58 pixels past the right edge of
            // every menu in the app, with no way for the label to give.
            Flexible(
              child: Text(
                name,
                // Two lines, into the height the row now grows to. One line
                // ellipsized the label instead of using that room, so at 320px
                // and text scale 2.0 a command read as a cut-off word - and
                // "Sync history" is the only way into the record.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: fontStyle ??
                    ArDriveTypography.body.buttonNormalBold(
                      color: isDisabled
                          ? ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeAccentDisabled
                          : null,
                    ),
              ),
            ),
            if (icon != null &&
                iconAlignment ==
                    ArDriveArDriveDropdownItemTileIconAlignment.right) ...[
              const Spacer(),
              icon!.copyWith(
                color: isDisabled
                    ? ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentDisabled
                    : null,
              ),
            ]
          ],
        ),
      ),
    );
  }
}
