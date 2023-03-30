import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class ArDriveDropdownItemTile extends StatelessWidget {
  final String name;
  final ArDriveIcon icon;
  final bool isDisabled;

  const ArDriveDropdownItemTile({
    Key? key,
    required this.name,
    required this.icon,
    this.isDisabled = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 41.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 375,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: ArDriveTypography.body.buttonNormalBold(
                color: isDisabled
                    ? ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentDisabled
                    : null,
              ),
            ),
            icon.copyWith(
              color: isDisabled
                  ? ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeAccentDisabled
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
