import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory shadows() {
  return WidgetbookCategory(name: 'Shadows', widgets: [
    WidgetbookComponent(name: 'Shadows Dark', useCases: [
      WidgetbookUseCase(
          name: '20%',
          builder: (context) {
            return ArDriveTheme(
              child: _Container(
                shadow:
                    ArDriveShadows(ArDriveTheme.of(context).themeData.colors)
                        .boxShadow20(),
              ),
            );
          }),
      WidgetbookUseCase(
          name: '40%',
          builder: (context) {
            return ArDriveTheme(
              child: _Container(
                shadow:
                    ArDriveShadows(ArDriveTheme.of(context).themeData.colors)
                        .boxShadow40(),
              ),
            );
          }),
      WidgetbookUseCase(
          name: '60%',
          builder: (context) {
            return ArDriveTheme(
              child: _Container(
                shadow:
                    ArDriveShadows(ArDriveTheme.of(context).themeData.colors)
                        .boxShadow60(),
              ),
            );
          }),
      WidgetbookUseCase(
          name: '80%',
          builder: (context) {
            return ArDriveTheme(
              child: _Container(
                shadow:
                    ArDriveShadows(ArDriveTheme.of(context).themeData.colors)
                        .boxShadow80(),
              ),
            );
          }),
      WidgetbookUseCase(
          name: '100%',
          builder: (context) {
            return ArDriveTheme(
              child: _Container(
                shadow:
                    ArDriveShadows(ArDriveTheme.of(context).themeData.colors)
                        .boxShadow100(),
              ),
            );
          })
    ]),
    WidgetbookComponent(name: 'Shadows Light', useCases: [
      WidgetbookUseCase(
          name: '20%',
          builder: (context) {
            return ArDriveTheme(
              themeData: lightTheme(),
              child: _Container(
                shadow: ArDriveShadows(lightTheme().colors).boxShadow20(),
              ),
            );
          }),
      WidgetbookUseCase(
          name: '40%',
          builder: (context) {
            return ArDriveTheme(
              themeData: lightTheme(),
              child: _Container(
                shadow: ArDriveShadows(lightTheme().colors).boxShadow40(),
              ),
            );
          }),
      WidgetbookUseCase(
          name: '60%',
          builder: (context) {
            return ArDriveTheme(
              themeData: lightTheme(),
              child: _Container(
                shadow: ArDriveShadows(lightTheme().colors).boxShadow60(),
              ),
            );
          }),
      WidgetbookUseCase(
          name: '80%',
          builder: (context) {
            return ArDriveTheme(
              themeData: lightTheme(),
              child: _Container(
                shadow: ArDriveShadows(lightTheme().colors).boxShadow80(),
              ),
            );
          }),
      WidgetbookUseCase(
          name: '100%',
          builder: (context) {
            return ArDriveTheme(
              themeData: lightTheme(),
              child: _Container(
                shadow: ArDriveShadows(lightTheme().colors).boxShadow100(),
              ),
            );
          })
    ])
  ]);
}

class _Container extends StatelessWidget {
  const _Container({
    super.key,
    required this.shadow,
  });
  final BoxShadow shadow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 200,
        width: 200,
        decoration: BoxDecoration(
          color: ArDriveTheme.of(context).themeData.backgroundColor,
          boxShadow: [shadow],
          borderRadius: BorderRadius.circular(
            12,
          ),
        ),
      ),
    );
  }
}
