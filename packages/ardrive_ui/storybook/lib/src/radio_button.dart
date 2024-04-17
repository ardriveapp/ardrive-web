import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory radioButton() {
  return WidgetbookCategory(name: 'RadioButton', children: [
    WidgetbookComponent(name: 'RadioButton', useCases: [
      WidgetbookUseCase(
          name: 'Single Radio Button',
          builder: (context) {
            return ArDriveStorybookAppBase(
              builder: (context) => const Center(
                child: ArDriveRadioButton(
                  text: 'Option 1',
                ),
              ),
            );
          }),
      WidgetbookUseCase(
          name: 'Radio Group',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              return const Scaffold(
                body: Align(
                  child: RadioGroupExample(),
                ),
              );
            });
          })
    ])
  ]);
}

class RadioGroupExample extends StatefulWidget {
  const RadioGroupExample({super.key});

  @override
  State<RadioGroupExample> createState() => _RadioGroupExampleState();
}

class _RadioGroupExampleState extends State<RadioGroupExample> {
  String? option;

  @override
  Widget build(BuildContext context) {
    final options = [
      /// Starts with the first enabled
      RadioButtonOptions(
        text: 'Option 1',
        value: true,
      ),
      RadioButtonOptions(text: 'Option 2'),
      RadioButtonOptions(text: 'Option 3'),
      RadioButtonOptions(text: 'Option 4'),
    ];

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ArDriveRadioButtonGroup(
            alignment: context.knobs.options(
              label: 'Alignment',
              labelBuilder: (alignment) => alignment.toString(),
              options: [
                Alignment.centerLeft,
                Alignment.centerRight,
                Alignment.center
              ],
            ),
            builder: (i, button) => button,
            onChanged: (i, value) {
              if (value) {
                option = 'Selected option: ${options[i].text}';
              } else {
                option = '';
              }
              setState(() {});
            },
            options: options,
          ),
          const SizedBox(
            height: 32,
          ),
          Text(
            option ?? '',
            style: ArDriveTypography.body.buttonLargeBold(),
          ),
        ],
      ),
    );
  }
}
