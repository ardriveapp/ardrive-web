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

WidgetbookCategory getTypographyCategory(bool isDark) {
  ArDriveColors colors = isDark ? ArDriveColors.dark() : ArDriveColors.light();

  WidgetbookFolder getForegroundColors() {
    return WidgetbookFolder(name: 'Foreground Colors', widgets: [
      WidgetbookComponent(name: 'Colors', useCases: [
        WidgetbookUseCase(
          name: 'themeFgDefault',
          builder: (context) => _getContainer(colors.themeFgDefault),
        ),
        WidgetbookUseCase(
          name: 'themeFgMuted',
          builder: (context) => _getContainer(colors.themeFgMuted),
        ),
        WidgetbookUseCase(
          name: 'themeFgSubtle',
          builder: (context) => _getContainer(colors.themeFgSubtle),
        ),
        WidgetbookUseCase(
          name: 'themeFgOnAccent',
          builder: (context) => _getContainer(colors.themeFgOnAccent),
        ),
        WidgetbookUseCase(
          name: 'themeFgOnDisabled',
          builder: (context) => _getContainer(colors.themeFgOnDisabled),
        ),
        WidgetbookUseCase(
          name: 'themeFgDisabled',
          builder: (context) => _getContainer(colors.themeFgDisabled),
        ),
      ])
    ]);
  }

  WidgetbookFolder getBackgroundColors() {
    return WidgetbookFolder(name: 'Background Colors', widgets: [
      WidgetbookComponent(name: 'Colors', useCases: [
        WidgetbookUseCase(
          name: 'themeBgSurface',
          builder: (context) => _getContainer(colors.themeBgSurface),
        ),
        WidgetbookUseCase(
          name: 'themeGbMuted',
          builder: (context) => _getContainer(colors.themeGbMuted),
        ),
        WidgetbookUseCase(
          name: 'themeBgSubtle',
          builder: (context) => _getContainer(colors.themeBgSubtle),
        ),
        WidgetbookUseCase(
          name: 'themeBgCanvas',
          builder: (context) => _getContainer(colors.themeBgCanvas),
        ),
      ])
    ]);
  }

  WidgetbookFolder getAccentColors() {
    return WidgetbookFolder(name: 'Accent colors', widgets: [
      WidgetbookComponent(name: 'Colors', useCases: [
        WidgetbookUseCase(
          name: 'themeAccentBrand',
          builder: (context) => _getContainer(colors.themeAccentBrand),
        ),
      ])
    ]);
  }

  WidgetbookFolder getWarningColors() {
    return WidgetbookFolder(name: 'Warning colors', widgets: [
      WidgetbookComponent(name: 'Colors', useCases: [
        WidgetbookUseCase(
          name: 'themeWarningFb',
          builder: (context) => _getContainer(colors.themeWarningFg),
        ),
        WidgetbookUseCase(
          name: 'themeWarningEmphasis',
          builder: (context) => _getContainer(colors.themeWarningEmphasis),
        ),
        WidgetbookUseCase(
          name: 'themeWarningMuted',
          builder: (context) => _getContainer(colors.themeWarningMuted),
        ),
        WidgetbookUseCase(
          name: 'themeWarningSubtle',
          builder: (context) => _getContainer(colors.themeWarningSubtle),
        ),
        WidgetbookUseCase(
          name: 'themeWarningOnWarning',
          builder: (context) => _getContainer(colors.themeWarningOnWarning),
        ),
      ])
    ]);
  }

  WidgetbookFolder getErrorColors() {
    return WidgetbookFolder(name: 'Error colors', widgets: [
      WidgetbookComponent(name: 'Colors', useCases: [
        WidgetbookUseCase(
          name: 'themeErrorFb',
          builder: (context) => _getContainer(colors.themeErrorFg),
        ),
        WidgetbookUseCase(
          name: 'themeErrorMuted',
          builder: (context) => _getContainer(colors.themeErrorMuted),
        ),
        WidgetbookUseCase(
          name: 'themeErrorSubtle',
          builder: (context) => _getContainer(colors.themeErrorSubtle),
        ),
        WidgetbookUseCase(
          name: 'themeErrorOnError',
          builder: (context) => _getContainer(colors.themeErrorOnError),
        ),
      ])
    ]);
  }

  WidgetbookFolder getInfoColors() {
    return WidgetbookFolder(name: 'Info colors', widgets: [
      WidgetbookComponent(name: 'Colors', useCases: [
        WidgetbookUseCase(
          name: 'themeInfoFb',
          builder: (context) => _getContainer(colors.themeInfoFb),
        ),
        WidgetbookUseCase(
          name: 'themeInfoEmphasis',
          builder: (context) => _getContainer(colors.themeInfoEmphasis),
        ),
        WidgetbookUseCase(
          name: 'themeInfoMuted',
          builder: (context) => _getContainer(colors.themeInfoMuted),
        ),
        WidgetbookUseCase(
          name: 'themeInfoSubtle',
          builder: (context) => _getContainer(colors.themeInfoSubtle),
        ),
        WidgetbookUseCase(
          name: 'themeInfoOnInfo',
          builder: (context) => _getContainer(colors.themeInfoOnInfo),
        ),
      ])
    ]);
  }

  WidgetbookFolder getInputColors() {
    return WidgetbookFolder(name: 'Input colors', widgets: [
      WidgetbookComponent(name: 'Colors', useCases: [
        WidgetbookUseCase(
          name: 'themeInputBackground',
          builder: (context) => _getContainer(colors.themeInputBackground),
        ),
        WidgetbookUseCase(
          name: 'themeInputText',
          builder: (context) => _getContainer(colors.themeInputText),
        ),
        WidgetbookUseCase(
          name: 'themeInputPlaceholder',
          builder: (context) => _getContainer(colors.themeInputPlaceholder),
        ),
        WidgetbookUseCase(
          name: 'themeInputBorderDisabled',
          builder: (context) => _getContainer(colors.themeInputBorderDisabled),
        ),
        WidgetbookUseCase(
          name: 'themeInputFbDisabled',
          builder: (context) => _getContainer(colors.themeInputFbDisabled),
        ),
        WidgetbookUseCase(
          name: 'themeBorderDefault',
          builder: (context) => _getContainer(colors.themeBorderDefault),
        ),
      ])
    ]);
  }

  WidgetbookFolder getSuccessColors() {
    return WidgetbookFolder(name: 'Success Colors', widgets: [
      WidgetbookComponent(name: 'Colors', useCases: [
        WidgetbookUseCase(
          name: 'themeSuccessFb',
          builder: (context) => _getContainer(colors.themeSuccessFb),
        ),
        WidgetbookUseCase(
          name: 'themeSuccessEmphasis',
          builder: (context) => _getContainer(colors.themeSuccessEmphasis),
        ),
        WidgetbookUseCase(
          name: 'themeSuccessMuted',
          builder: (context) => _getContainer(colors.themeSuccessMuted),
        ),
        WidgetbookUseCase(
          name: 'themeSuccessMuted',
          builder: (context) => _getContainer(colors.themeSuccessMuted),
        ),
        WidgetbookUseCase(
          name: 'themeSuccessSubtle',
          builder: (context) => _getContainer(colors.themeSuccessSubtle),
        ),
        WidgetbookUseCase(
          name: 'themeSuccessMuted',
          builder: (context) => _getContainer(colors.themeSuccessMuted),
        ),
        WidgetbookUseCase(
          name: 'themeSuccessOnSuccess',
          builder: (context) => _getContainer(colors.themeSuccessOnSuccess),
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
                  _getContainer(colors.themeOverlayBackground),
            ),
          ],
        ),
      ],
    );
  }

  return WidgetbookCategory(
      name: isDark ? 'Light Colors' : 'Dark Colors',
      folders: [
        getForegroundColors(),
        getBackgroundColors(),
        getWarningColors(),
        getErrorColors(),
        getInfoColors(),
        getInputColors(),
        getSuccessColors(),
        getOverlayColors(),
        getAccentColors(),
      ]);
}
