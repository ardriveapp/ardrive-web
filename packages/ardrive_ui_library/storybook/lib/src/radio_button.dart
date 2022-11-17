import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/basic.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory radioButton() {
  return WidgetbookCategory(name: 'RadioButton', widgets: [
    WidgetbookComponent(name: 'RadioButton', useCases: [
      WidgetbookUseCase(
          name: 'name',
          builder: (context) {
            return Row(
              children: [
                ArDriveRadioButton(
                  text: 'Option 1',
                ),
              ],
            );
          }),
      WidgetbookUseCase(
          name: 'Toggle Group',
          builder: (context) {
            return ArDriveApp(builder: (context) {
              return const RadioGroupExample();
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
        children: [
          ArDriveRadioButtonGroup(
            onChanged: (i, value) {
              if (value) {
                option = options[i].text;
              } else {
                option = '';
              }
              setState(() {});
            },
            options: options,
          ),
          Text(option ?? ''),
        ],
      ),
    );
  }
}
