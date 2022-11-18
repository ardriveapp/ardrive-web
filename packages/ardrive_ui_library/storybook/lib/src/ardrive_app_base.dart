import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

class ArDriveStorybookAppBase extends StatelessWidget {
  const ArDriveStorybookAppBase({
    super.key,
    required this.builder,
  });

  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) {
    final themes = context.knobs.options(label: 'Themes', options: [
      Option(
        label: 'Dark',
        value: ArDriveThemeData(),
      ),
      Option(
        label: 'Light',
        value: lightTheme(),
      ),
    ]);
    return ArDriveApp(
      themeData: themes,
      builder: (context) {
        return MaterialApp(
          theme: themes.materialThemeData,
          home: Scaffold(
            key: ValueKey(themes.name),
            body: Center(
              child: builder(context),
            ),
          ),
        );
      },
    );
  }
}
