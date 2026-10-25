import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class UnpreviewableContent extends StatelessWidget {
  const UnpreviewableContent({super.key});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: Padding(
          padding: const EdgeInsets.all(ArDriveSpacing.md),
          child: Column(
            children: [
              ExcludeSemantics(
                child: ArDriveIcons.triangle(
                  size: 24,
                  color: colorTokens.iconMid,
                ),
              ),
              const SizedBox(height: ArDriveSpacing.sm),
              Text(
                appLocalizationsOf(context).couldNotLoadFile,
                style: ArDriveTypographyNew.of(context).paragraphNormal(
                  color: colorTokens.textHigh,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
