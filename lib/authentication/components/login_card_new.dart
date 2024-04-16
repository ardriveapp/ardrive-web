import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';

class LoginCardNew extends StatelessWidget {
  const LoginCardNew({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 100,
          maxWidth: 450,
          minWidth: 450,
        ),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: colorTokens.containerL3,
            borderRadius: BorderRadius.circular(9),
          ),
          child: child,
        ));
  }
}
