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
      padding: const EdgeInsets.symmetric(horizontal: 18.0),
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            icon.copyWith(
              color: isDisabled
                  ? ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeAccentDisabled
                  : null,
            ),
            const SizedBox(width: 20),
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
          ],
        ),
      ),
    );
  }
}
