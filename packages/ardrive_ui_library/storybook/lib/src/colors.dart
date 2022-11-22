import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory getColors() {
  return WidgetbookCategory(name: 'Colors', widgets: [
    WidgetbookComponent(name: 'Colors', useCases: [
      WidgetbookUseCase(
          name: 'Foreground',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final colors = ArDriveTheme.of(context).themeData.colors;
              return Center(
                child: Container(
                  height: 120,
                  width: 120,
                  color: context.knobs.options(label: 'Colors', options: [
                    Option(
                      label: 'themeFgDefault',
                      value: colors.themeFgDefault,
                    ),
                    Option(
                      label: 'themeFgMuted',
                      value: colors.themeFgMuted,
                    ),
                    Option(
                      label: 'themeFgSubtle',
                      value: colors.themeFgSubtle,
                    ),
                    Option(
                      label: 'themeFgOnDisabled',
                      value: colors.themeFgOnDisabled,
                    ),
                    Option(
                      label: 'themeFgOnAccent',
                      value: colors.themeFgOnAccent,
                    ),
                    Option(
                      label: 'themeFgDisabled',
                      value: colors.themeFgDisabled,
                    ),
                  ]),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Background',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final colors = ArDriveTheme.of(context).themeData.colors;
              return Center(
                child: Container(
                  height: 120,
                  width: 120,
                  color: context.knobs.options(label: 'Colors', options: [
                    Option(
                      label: 'themeBgSurface',
                      value: colors.themeBgSurface,
                    ),
                    Option(
                      label: 'themeGbMuted',
                      value: colors.themeGbMuted,
                    ),
                    Option(
                      label: 'themeBgSubtle',
                      value: colors.themeBgSubtle,
                    ),
                    Option(
                      label: 'themeBgCanvas',
                      value: colors.themeBgCanvas,
                    ),
                  ]),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Accent',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final colors = ArDriveTheme.of(context).themeData.colors;
              return Center(
                child: Container(
                  height: 120,
                  width: 120,
                  color: context.knobs.options(label: 'Colors', options: [
                    Option(
                      label: 'themeAccentBrand',
                      value: colors.themeAccentBrand,
                    ),
                    Option(
                      label: 'themeAccentDisabled',
                      value: colors.themeAccentDisabled,
                    ),
                    Option(
                      label: 'themeAccentEmphasis',
                      value: colors.themeAccentEmphasis,
                    ),
                    Option(
                      label: 'themeAccentMuted',
                      value: colors.themeAccentMuted,
                    ),
                    Option(
                      label: 'themeAccentSubtle',
                      value: colors.themeAccentSubtle,
                    ),
                  ]),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Warning',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final colors = ArDriveTheme.of(context).themeData.colors;
              return Center(
                child: Container(
                  height: 120,
                  width: 120,
                  color: context.knobs.options(label: 'Colors', options: [
                    Option(
                      label: 'themeWarningFg',
                      value: colors.themeWarningFg,
                    ),
                    Option(
                      label: 'themeWarningEmphasis',
                      value: colors.themeWarningEmphasis,
                    ),
                    Option(
                      label: 'themeWarningMuted',
                      value: colors.themeWarningMuted,
                    ),
                    Option(
                      label: 'themeWarningSubtle',
                      value: colors.themeWarningSubtle,
                    ),
                    Option(
                      label: 'themeWarningOnWarning',
                      value: colors.themeWarningOnWarning,
                    ),
                  ]),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Error',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final colors = ArDriveTheme.of(context).themeData.colors;
              return Center(
                child: Container(
                  height: 120,
                  width: 120,
                  color: context.knobs.options(label: 'Colors', options: [
                    Option(
                      label: 'themeErrorFg',
                      value: colors.themeErrorFg,
                    ),
                    Option(
                      label: 'themeErrorMuted',
                      value: colors.themeErrorMuted,
                    ),
                    Option(
                      label: 'themeErrorSubtle',
                      value: colors.themeErrorSubtle,
                    ),
                    Option(
                      label: 'themeErrorOnError',
                      value: colors.themeErrorOnError,
                    ),
                  ]),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Info',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final colors = ArDriveTheme.of(context).themeData.colors;
              return Center(
                child: Container(
                  height: 120,
                  width: 120,
                  color: context.knobs.options(label: 'Colors', options: [
                    Option(
                      label: 'themeInfoFb',
                      value: colors.themeInfoFb,
                    ),
                    Option(
                      label: 'themeInfoEmphasis',
                      value: colors.themeInfoEmphasis,
                    ),
                    Option(
                      label: 'themeInfoMuted',
                      value: colors.themeInfoMuted,
                    ),
                    Option(
                      label: 'themeInfoSubtle',
                      value: colors.themeInfoSubtle,
                    ),
                    Option(
                      label: 'themeInfoOnInfo',
                      value: colors.themeInfoOnInfo,
                    ),
                  ]),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Success',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final colors = ArDriveTheme.of(context).themeData.colors;
              return Center(
                child: Container(
                  height: 120,
                  width: 120,
                  color: context.knobs.options(label: 'Colors', options: [
                    Option(
                      label: 'themeSuccessFb',
                      value: colors.themeSuccessFb,
                    ),
                    Option(
                      label: 'themeSuccessEmphasis',
                      value: colors.themeSuccessEmphasis,
                    ),
                    Option(
                      label: 'themeSuccessMuted',
                      value: colors.themeSuccessMuted,
                    ),
                    Option(
                      label: 'themeSuccessSubtle',
                      value: colors.themeSuccessSubtle,
                    ),
                    Option(
                      label: 'themeSuccessOnSuccess',
                      value: colors.themeSuccessOnSuccess,
                    ),
                  ]),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Overlay',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final colors = ArDriveTheme.of(context).themeData.colors;
              return Center(
                child: Container(
                  height: 120,
                  width: 120,
                  color: context.knobs.options(label: 'Colors', options: [
                    Option(
                      label: 'themeOverlayBackground',
                      value: colors.themeOverlayBackground,
                    ),
                  ]),
                ),
              );
            });
          }),
    ]),
  ]);
}
