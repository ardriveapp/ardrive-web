import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

class ColorOption {
  final String name;
  final Color value;
  String get description => value.toString();

  const ColorOption({required this.name, required this.value});
}

WidgetbookCategory getColors() {
  return WidgetbookCategory(name: 'Colors', children: [
    WidgetbookComponent(name: 'Colors', useCases: [
      WidgetbookUseCase(
          name: 'Foreground',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final lightColors = lightTheme().colors;
              final darkTheme = ArDriveThemeData().colors;

              List<ColorOption> foregroundLight = [
                ColorOption(
                  name: 'themeFgDefault',
                  value: lightColors.themeFgDefault,
                ),
                ColorOption(
                  name: 'themeFgMuted',
                  value: lightColors.themeFgMuted,
                ),
                ColorOption(
                  name: 'themeFgSubtle',
                  value: lightColors.themeFgSubtle,
                ),
                ColorOption(
                  name: 'themeFgOnDisabled',
                  value: lightColors.themeFgOnDisabled,
                ),
                ColorOption(
                  name: 'themeFgOnAccent',
                  value: lightColors.themeFgOnAccent,
                ),
                ColorOption(
                  name: 'themeFgDisabled',
                  value: lightColors.themeFgDisabled,
                ),
              ];

              List<ColorOption> foregroundDark = [
                ColorOption(
                  name: 'themeFgDefault',
                  value: darkTheme.themeFgDefault,
                ),
                ColorOption(
                  name: 'themeFgMuted',
                  value: darkTheme.themeFgMuted,
                ),
                ColorOption(
                  name: 'themeFgSubtle',
                  value: darkTheme.themeFgSubtle,
                ),
                ColorOption(
                  name: 'themeFgOnDisabled',
                  value: darkTheme.themeFgOnDisabled,
                ),
                ColorOption(
                  name: 'themeFgOnAccent',
                  value: darkTheme.themeFgOnAccent,
                ),
                ColorOption(
                  name: 'themeFgDisabled',
                  value: darkTheme.themeFgDisabled,
                ),
              ];

              return _colorWidget(
                context,
                optionsDark: foregroundDark,
                optionsLight: foregroundLight,
              );
            });
          }),
      WidgetbookUseCase(
        name: 'Background',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            final lightColors = lightTheme().colors;
            final darkTheme = ArDriveThemeData().colors;

            List<ColorOption> backgroundLight = [
              ColorOption(
                name: 'themeBgSurface',
                value: lightColors.themeBgSurface,
              ),
              ColorOption(
                name: 'themeGbMuted',
                value: lightColors.themeGbMuted,
              ),
              ColorOption(
                name: 'themeBgSubtle',
                value: lightColors.themeBgSubtle,
              ),
              ColorOption(
                name: 'themeBgCanvas',
                value: lightColors.themeBgCanvas,
              ),
            ];

            List<ColorOption> backgroundDark = [
              ColorOption(
                name: 'themeBgSurface',
                value: darkTheme.themeBgSurface,
              ),
              ColorOption(
                name: 'themeGbMuted',
                value: darkTheme.themeGbMuted,
              ),
              ColorOption(
                name: 'themeBgSubtle',
                value: darkTheme.themeBgSubtle,
              ),
              ColorOption(
                name: 'themeBgCanvas',
                value: darkTheme.themeBgCanvas,
              ),
            ];

            return _colorWidget(
              context,
              optionsDark: backgroundDark,
              optionsLight: backgroundLight,
            );
          });
        },
      ),
      WidgetbookUseCase(
        name: 'Accent',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            // light
            final lightColors = lightTheme().colors;
            final darkTheme = ArDriveThemeData().colors;

            List<ColorOption> accentLight = [
              ColorOption(
                name: 'themeAccentBrand',
                value: lightColors.themeAccentBrand,
              ),
              ColorOption(
                name: 'themeAccentDisabled',
                value: lightColors.themeAccentDisabled,
              ),
              ColorOption(
                name: 'themeAccentEmphasis',
                value: lightColors.themeAccentEmphasis,
              ),
              ColorOption(
                name: 'themeAccentMuted',
                value: lightColors.themeAccentMuted,
              ),
              ColorOption(
                name: 'themeAccentSubtle',
                value: lightColors.themeAccentSubtle,
              ),
            ];

            List<ColorOption> accentDark = [
              ColorOption(
                name: 'themeAccentBrand',
                value: darkTheme.themeAccentBrand,
              ),
              ColorOption(
                name: 'themeAccentDisabled',
                value: darkTheme.themeAccentDisabled,
              ),
              ColorOption(
                name: 'themeAccentEmphasis',
                value: darkTheme.themeAccentEmphasis,
              ),
              ColorOption(
                name: 'themeAccentMuted',
                value: darkTheme.themeAccentMuted,
              ),
              ColorOption(
                name: 'themeAccentSubtle',
                value: darkTheme.themeAccentSubtle,
              ),
            ];

            return _colorWidget(context,
                optionsDark: accentDark, optionsLight: accentLight);
          });
        },
      ),
      WidgetbookUseCase(
        name: 'Warning',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            final lightColors = lightTheme().colors;
            final darkTheme = ArDriveThemeData().colors;

            List<ColorOption> warningLight = [
              ColorOption(
                name: 'themeWarningFg',
                value: lightColors.themeWarningFg,
              ),
              ColorOption(
                name: 'themeWarningEmphasis',
                value: lightColors.themeWarningEmphasis,
              ),
              ColorOption(
                name: 'themeWarningMuted',
                value: lightColors.themeWarningMuted,
              ),
              ColorOption(
                name: 'themeWarningSubtle',
                value: lightColors.themeWarningSubtle,
              ),
              ColorOption(
                name: 'themeWarningOnWarning',
                value: lightColors.themeWarningOnWarning,
              ),
            ];

            List<ColorOption> warningDark = [
              ColorOption(
                name: 'themeWarningFg',
                value: darkTheme.themeWarningFg,
              ),
              ColorOption(
                name: 'themeWarningEmphasis',
                value: darkTheme.themeWarningEmphasis,
              ),
              ColorOption(
                name: 'themeWarningMuted',
                value: darkTheme.themeWarningMuted,
              ),
              ColorOption(
                name: 'themeWarningSubtle',
                value: darkTheme.themeWarningSubtle,
              ),
              ColorOption(
                name: 'themeWarningOnWarning',
                value: darkTheme.themeWarningOnWarning,
              ),
            ];

            return _colorWidget(context,
                optionsDark: warningDark, optionsLight: warningLight);
          });
        },
      ),
      WidgetbookUseCase(
        name: 'Error',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            final lightColors = lightTheme().colors;
            final darkTheme = ArDriveThemeData().colors;

            List<ColorOption> errorLight = [
              ColorOption(
                name: 'themeErrorFg',
                value: lightColors.themeErrorFg,
              ),
              ColorOption(
                name: 'themeErrorMuted',
                value: lightColors.themeErrorMuted,
              ),
              ColorOption(
                name: 'themeErrorSubtle',
                value: lightColors.themeErrorSubtle,
              ),
              ColorOption(
                name: 'themeErrorOnError',
                value: lightColors.themeErrorOnError,
              ),
            ];

            List<ColorOption> errorDark = [
              ColorOption(
                name: 'themeErrorFg',
                value: darkTheme.themeErrorFg,
              ),
              ColorOption(
                name: 'themeErrorMuted',
                value: darkTheme.themeErrorMuted,
              ),
              ColorOption(
                name: 'themeErrorSubtle',
                value: darkTheme.themeErrorSubtle,
              ),
              ColorOption(
                name: 'themeErrorOnError',
                value: darkTheme.themeErrorOnError,
              ),
            ];

            return _colorWidget(context,
                optionsDark: errorDark, optionsLight: errorLight);
          });
        },
      ),
      WidgetbookUseCase(
        name: 'Info',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            final lightColors = lightTheme().colors;
            final darkTheme = ArDriveThemeData().colors;

            List<ColorOption> infoLight = [
              ColorOption(
                name: 'themeInfoFb',
                value: lightColors.themeInfoFb,
              ),
              ColorOption(
                name: 'themeInfoEmphasis',
                value: lightColors.themeInfoEmphasis,
              ),
              ColorOption(
                name: 'themeInfoMuted',
                value: lightColors.themeInfoMuted,
              ),
              ColorOption(
                name: 'themeInfoSubtle',
                value: lightColors.themeInfoSubtle,
              ),
              ColorOption(
                name: 'themeInfoOnInfo',
                value: lightColors.themeInfoOnInfo,
              ),
            ];

            List<ColorOption> infoDark = [
              ColorOption(
                name: 'themeInfoFb',
                value: darkTheme.themeInfoFb,
              ),
              ColorOption(
                name: 'themeInfoEmphasis',
                value: darkTheme.themeInfoEmphasis,
              ),
              ColorOption(
                name: 'themeInfoMuted',
                value: darkTheme.themeInfoMuted,
              ),
              ColorOption(
                name: 'themeInfoSubtle',
                value: darkTheme.themeInfoSubtle,
              ),
              ColorOption(
                name: 'themeInfoOnInfo',
                value: darkTheme.themeInfoOnInfo,
              ),
            ];

            return _colorWidget(context,
                optionsDark: infoDark, optionsLight: infoLight);
          });
        },
      ),
      WidgetbookUseCase(
        name: 'Success',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            final lightColors = lightTheme().colors;
            final darkTheme = ArDriveThemeData().colors;

            List<ColorOption> successLight = [
              ColorOption(
                name: 'themeSuccessFb',
                value: lightColors.themeSuccessFb,
              ),
              ColorOption(
                name: 'themeSuccessEmphasis',
                value: lightColors.themeSuccessEmphasis,
              ),
              ColorOption(
                name: 'themeSuccessMuted',
                value: lightColors.themeSuccessMuted,
              ),
              ColorOption(
                name: 'themeSuccessSubtle',
                value: lightColors.themeSuccessSubtle,
              ),
              ColorOption(
                name: 'themeSuccessOnSuccess',
                value: lightColors.themeSuccessOnSuccess,
              ),
            ];

            List<ColorOption> successDark = [
              ColorOption(
                name: 'themeSuccessFb',
                value: darkTheme.themeSuccessFb,
              ),
              ColorOption(
                name: 'themeSuccessEmphasis',
                value: darkTheme.themeSuccessEmphasis,
              ),
              ColorOption(
                name: 'themeSuccessMuted',
                value: darkTheme.themeSuccessMuted,
              ),
              ColorOption(
                name: 'themeSuccessSubtle',
                value: darkTheme.themeSuccessSubtle,
              ),
              ColorOption(
                name: 'themeSuccessOnSuccess',
                value: darkTheme.themeSuccessOnSuccess,
              ),
            ];

            return _colorWidget(context,
                optionsDark: successDark, optionsLight: successLight);
          });
        },
      ),
      WidgetbookUseCase(
        name: 'Overlay',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            final colors = ArDriveTheme.of(context).themeData.colors;

            List<ColorOption> overlay = [
              ColorOption(
                name: 'themeOverlayBackground',
                value: colors.themeOverlayBackground,
              ),
            ];

            return Center(
              child: Container(
                  height: 120,
                  width: 120,
                  color: context.knobs
                      .options<ColorOption>(
                        label: 'Colors',
                        labelBuilder: (c) => c.name,
                        options: overlay,
                      )
                      .value),
            );
          });
        },
      ),
    ]),
  ]);
}

Widget _colorWidget(BuildContext context,
    {required List<ColorOption> optionsLight,
    required List<ColorOption> optionsDark}) {
  return Center(
      child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ColoredContainer(
        color: context.knobs.options<ColorOption>(
          label: 'Light',
          labelBuilder: (c) => c.name,
          options: optionsLight,
        ),
        textLabel: 'Light',
      ),
      const SizedBox(height: 20),
      ColoredContainer(
        color: context.knobs.options<ColorOption>(
          label: 'Dark',
          labelBuilder: (c) => c.name,
          options: optionsDark,
        ),
        textLabel: 'Dark',
      ),
    ],
  ));
}

class ColoredContainer extends StatelessWidget {
  const ColoredContainer({
    required this.color,
    required this.textLabel,
    super.key,
  });

  final ColorOption color;
  final String textLabel;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness =
        ThemeData.estimateBrightnessForColor(color.value);
    final bool useWhiteForeground = brightness == Brightness.dark;

    final Color foregroundColor =
        useWhiteForeground ? Colors.white : Colors.black;

    return Container(
      height: 300,
      width: 300,
      color: color.value,
      child: Center(
        child: Text(
          '$textLabel\n${color.description}',
          style: ArDriveTypography.body.buttonLargeBold(color: foregroundColor),
        ),
      ),
    );
  }
}
