import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class UnpreviewableContent extends StatelessWidget {
  const UnpreviewableContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Column(
          children: [
            const Icon(Icons.error_outline_outlined, size: 20),
            Text(
              appLocalizationsOf(context).couldNotLoadFile,
              style: ArDriveTypography.body.smallBold700(
                color: ArDriveTheme.of(context).themeData.colors.themeFgMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
