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
        height: height ?? 48,
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
            Text(
              name,
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
