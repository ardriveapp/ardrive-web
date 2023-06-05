import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class TurboTopupScaffold extends StatelessWidget {
  final Widget child;

  const TurboTopupScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40.0),
      color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: ArDriveClickArea(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: ArDriveIcons.x(),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
