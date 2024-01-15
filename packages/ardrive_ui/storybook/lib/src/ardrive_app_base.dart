import 'package:ardrive_ui/ardrive_ui.dart';
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
    final themes = context.knobs.options<ArDriveThemeData>(
      labelBuilder: (t) => t.name,
      label: 'Themes',
      options: [
        ArDriveThemeData(),
        lightTheme(),
      ],
    );
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: ArDriveApp(
        themeData: themes,
        builder: (context) {
          return MaterialApp(
            theme: themes.materialThemeData,
            home: Scaffold(
              body: Center(
                child: builder(context),
              ),
            ),
          );
        },
      ),
    );
  }
}
