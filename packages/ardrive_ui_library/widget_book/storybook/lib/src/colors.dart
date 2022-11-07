import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

Widget _getContainer(Color color) {
  return Center(
    child: Container(
      height: 120,
      width: 120,
      color: color,
    ),
  );
}

WidgetbookFolder getForegroundColors() {
  return WidgetbookFolder(name: 'Foreground Colors', widgets: [
    WidgetbookComponent(name: 'Colors', useCases: [
      WidgetbookUseCase(
        name: 'themeFgDefault',
        builder: (context) => _getContainer(ArDriveColors.themeFgDefault),
      ),
      WidgetbookUseCase(
        name: 'themeFgMuted',
        builder: (context) => _getContainer(ArDriveColors.themeFgMuted),
      ),
      WidgetbookUseCase(
        name: 'themeFgSubtle',
        builder: (context) => _getContainer(ArDriveColors.themeFgSubtle),
      ),
      WidgetbookUseCase(
        name: 'themeFgOnAccent',
        builder: (context) => _getContainer(ArDriveColors.themeFgOnAccent),
      ),
      WidgetbookUseCase(
        name: 'themeFgOnDisabled',
        builder: (context) => _getContainer(ArDriveColors.themeFgOnDisabled),
      ),
      WidgetbookUseCase(
        name: 'themeFgDisabled',
        builder: (context) => _getContainer(ArDriveColors.themeFgDisabled),
      ),
    ])
  ]);
}

WidgetbookFolder getBackgroundColors() {
  return WidgetbookFolder(name: 'Background Colors', widgets: [
    WidgetbookComponent(name: 'Colors', useCases: [
      WidgetbookUseCase(
        name: 'themeBgSurface',
        builder: (context) => _getContainer(ArDriveColors.themeBgSurface),
      ),
      WidgetbookUseCase(
        name: 'themeGbmuted',
        builder: (context) => _getContainer(ArDriveColors.themeGbmuted),
      ),
      WidgetbookUseCase(
        name: 'themeBgSubtle',
        builder: (context) => _getContainer(ArDriveColors.themeBgSubtle),
      ),
      WidgetbookUseCase(
        name: 'themeBgCanvas',
        builder: (context) => _getContainer(ArDriveColors.themeBgCanvas),
      ),
    ])
  ]);
}

WidgetbookFolder getAccentColors() {
  return WidgetbookFolder(name: 'Accent colors', widgets: [
    WidgetbookComponent(name: 'Colors', useCases: [
      WidgetbookUseCase(
        name: 'themeAccentBrand',
        builder: (context) => _getContainer(ArDriveColors.themeAccentBrand),
      ),
    ])
  ]);
}

WidgetbookFolder getWarningColors() {
  return WidgetbookFolder(name: 'Warning colors', widgets: [
    WidgetbookComponent(name: 'Colors', useCases: [
      WidgetbookUseCase(
        name: 'themeWarningFb',
        builder: (context) => _getContainer(ArDriveColors.themeWarningFb),
      ),
      WidgetbookUseCase(
        name: 'themeWarningEmphasis',
        builder: (context) => _getContainer(ArDriveColors.themeWarningEmphasis),
      ),
      WidgetbookUseCase(
        name: 'themeWarningMuted',
        builder: (context) => _getContainer(ArDriveColors.themeWarningMuted),
      ),
      WidgetbookUseCase(
        name: 'themeWarningSubtle',
        builder: (context) => _getContainer(ArDriveColors.themeWarningSubtle),
      ),
      WidgetbookUseCase(
        name: 'themeWarningOnWarning',
        builder: (context) =>
            _getContainer(ArDriveColors.themeWarningOnWarning),
      ),
    ])
  ]);
}

WidgetbookFolder getErrorColors() {
  return WidgetbookFolder(name: 'Error colors', widgets: [
    WidgetbookComponent(name: 'Colors', useCases: [
      WidgetbookUseCase(
        name: 'themeErrorFb',
        builder: (context) => _getContainer(ArDriveColors.themeErrorFb),
      ),
      WidgetbookUseCase(
        name: 'themeErrorMuted',
        builder: (context) => _getContainer(ArDriveColors.themeErrorMuted),
      ),
      WidgetbookUseCase(
        name: 'themeErrorSubtle',
        builder: (context) => _getContainer(ArDriveColors.themeErrorSubtle),
      ),
      WidgetbookUseCase(
        name: 'themeErrorOnError',
        builder: (context) => _getContainer(ArDriveColors.themeErrorOnError),
      ),
    ])
  ]);
}

WidgetbookFolder getInfoColors() {
  return WidgetbookFolder(name: 'Info colors', widgets: [
    WidgetbookComponent(name: 'Colors', useCases: [
      WidgetbookUseCase(
        name: 'themeInfoFb',
        builder: (context) => _getContainer(ArDriveColors.themeInfoFb),
      ),
      WidgetbookUseCase(
        name: 'themeInfoEmphasis',
        builder: (context) => _getContainer(ArDriveColors.themeInfoEmphasis),
      ),
      WidgetbookUseCase(
        name: 'themeInfoMuted',
        builder: (context) => _getContainer(ArDriveColors.themeInfoMuted),
      ),
      WidgetbookUseCase(
        name: 'themeInfoSubtle',
        builder: (context) => _getContainer(ArDriveColors.themeInfoSubtle),
      ),
      WidgetbookUseCase(
        name: 'themeInfoOnInfo',
        builder: (context) => _getContainer(ArDriveColors.themeInfoOnInfo),
      ),
    ])
  ]);
}

WidgetbookFolder getInputColors() {
  return WidgetbookFolder(name: 'Input colors', widgets: [
    WidgetbookComponent(name: 'Colors', useCases: [
      WidgetbookUseCase(
        name: 'themeInputBackground',
        builder: (context) => _getContainer(ArDriveColors.themeInputBackground),
      ),
      WidgetbookUseCase(
        name: 'themeInputText',
        builder: (context) => _getContainer(ArDriveColors.themeInputText),
      ),
      WidgetbookUseCase(
        name: 'themeInputPlaceholder',
        builder: (context) =>
            _getContainer(ArDriveColors.themeInputPlaceholder),
      ),
      WidgetbookUseCase(
        name: 'themeInputBorderDisabled',
        builder: (context) =>
            _getContainer(ArDriveColors.themeInputBorderDisabled),
      ),
      WidgetbookUseCase(
        name: 'themeInputFbDisabled',
        builder: (context) => _getContainer(ArDriveColors.themeInputFbDisabled),
      ),
      WidgetbookUseCase(
        name: 'themeBorderDefault',
        builder: (context) => _getContainer(ArDriveColors.themeBorderDefault),
      ),
    ])
  ]);
}

WidgetbookFolder getSuccessColors() {
  return WidgetbookFolder(name: 'Success Colors', widgets: [
    WidgetbookComponent(name: 'Colors', useCases: [
      WidgetbookUseCase(
        name: 'themeSuccessFb',
        builder: (context) => _getContainer(ArDriveColors.themeSuccessFb),
      ),
      WidgetbookUseCase(
        name: 'themeSuccessEmphasis',
        builder: (context) => _getContainer(ArDriveColors.themeSuccessEmphasis),
      ),
      WidgetbookUseCase(
        name: 'themeSuccessMuted',
        builder: (context) => _getContainer(ArDriveColors.themeSuccessMuted),
      ),
      WidgetbookUseCase(
        name: 'themeSuccessMuted',
        builder: (context) => _getContainer(ArDriveColors.themeSuccessMuted),
      ),
      WidgetbookUseCase(
        name: 'themeSuccessSubtle',
        builder: (context) => _getContainer(ArDriveColors.themeSuccessSubtle),
      ),
      WidgetbookUseCase(
        name: 'themeSuccessMuted',
        builder: (context) => _getContainer(ArDriveColors.themeSuccessMuted),
      ),
      WidgetbookUseCase(
        name: 'themeSuccessOnSuccess',
        builder: (context) =>
            _getContainer(ArDriveColors.themeSuccessOnSuccess),
      ),
    ])
  ]);
}

WidgetbookFolder getOverlayColors() {
  return WidgetbookFolder(
    name: 'Overlay colors',
    widgets: [
      WidgetbookComponent(
        name: 'Colors',
        useCases: [
          WidgetbookUseCase(
            name: 'themeOverlayBackground',
            builder: (context) =>
                _getContainer(ArDriveColors.themeOverlayBackground),
          ),
        ],
      ),
    ],
  );
}
