import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TurboTopupScaffold extends StatelessWidget {
  final Widget child;
  final String? title;

  const TurboTopupScaffold({
    super.key,
    required this.child,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final themeData = ArDriveTheme.of(context).themeData;
    final colors = themeData.colors;
    final colorTokens = themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Red top line (ArDrive modal pattern)
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: colorTokens.containerRed,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
            ),
            // Main content
            Container(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              color: colors.themeBgCanvas,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: typography.heading5(
                        fontWeight: ArFontWeight.bold,
                        color: colors.themeFgDefault,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  child,
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          top: 20,
          child: ArDriveClickArea(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: ArDriveIcons.x(),
            ),
          ),
        ),
      ],
    );
  }
}
