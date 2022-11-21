import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/basic.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory radioButton() {
  return WidgetbookCategory(name: 'RadioButton', widgets: [
    WidgetbookComponent(name: 'RadioButton', useCases: [
      WidgetbookUseCase(
          name: 'Single Radio Button',
          builder: (context) {
            return const Center(
              child: ArDriveRadioButton(
                text: 'Option 1',
              ),
            );
          }),
      WidgetbookUseCase(
          name: 'Radio Group',
          builder: (context) {
            return ArDriveApp(builder: (context) {
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
      RadioButtonOptions(text: 'Option 1'),
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
              options: [
                const Option(label: 'Left', value: Alignment.centerLeft),
                const Option(label: 'Right', value: Alignment.centerRight),
                const Option(
                  label: 'Center',
                  value: Alignment.center,
                ),
              ],
            ),
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
