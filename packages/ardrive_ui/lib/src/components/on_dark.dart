import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';

/// Draws [child] with the dark theme's tokens, whichever theme the app is in.
///
/// For what sits on a surface that is dark in both themes, such as a video's
/// black stage. Text, icons, spinners, progress and buttons then take the
/// colours the dark theme gives them, rather than literal whites picked by
/// hand.
class ArDriveOnDark extends StatelessWidget {
  const ArDriveOnDark({super.key, required this.child});

  final Widget child;

  static final ArDriveThemeData _dark =
      ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode());

  @override
  Widget build(BuildContext context) {
    if (ArDriveTheme.of(context).themeData.name == _dark.name) return child;

    return ArDriveTheme(themeData: _dark, child: child);
  }
}
