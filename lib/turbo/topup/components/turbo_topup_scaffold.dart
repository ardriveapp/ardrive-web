import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TurboTopupScaffold extends StatelessWidget {
  final Widget child;

  const TurboTopupScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final themeData = ArDriveTheme.of(context).themeData;
    final colors = themeData.colors;
    final colorTokens = themeData.colorTokens;

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
              padding: const EdgeInsets.all(40.0),
              color: colors.themeBgCanvas,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  child,
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 27,
          top: 27,
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
