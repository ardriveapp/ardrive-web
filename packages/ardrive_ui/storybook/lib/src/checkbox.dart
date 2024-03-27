import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory checkBox() {
  return WidgetbookCategory(name: 'Check Box', children: [
    WidgetbookComponent(name: 'Check Box', useCases: [
      WidgetbookUseCase(
        name: 'Check Box',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            return const CheckBoxExample();
          });
        },
      ),
    ]),
  ]);
}

class CheckBoxExample extends StatefulWidget {
  const CheckBoxExample({super.key});

  @override
  State<CheckBoxExample> createState() => _CheckBoxExampleState();
}

class _CheckBoxExampleState extends State<CheckBoxExample> {
  bool _value = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _value = context.knobs.boolean(label: 'IsChecked', initialValue: true);
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled =
        context.knobs.boolean(label: 'IsEnabled', initialValue: true);
    final isIndeterminate =
        context.knobs.boolean(label: 'isIndeterminate', initialValue: false);
    return SizedBox(
      height: 300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ArDriveCheckBox(
            title:
                context.knobs.text(label: 'Title', initialValue: 'Select File'),
            checked: _value,
            isDisabled: !isEnabled,
            isIndeterminate: isIndeterminate,
            key: ValueKey('$isEnabled$_value$isIndeterminate'),
            onChange: (value) {
              setState(() {
                _value = value;
              });
            },
          ),
          Text('Check box is checked: ${_value.toString()}')
        ],
      ),
    );
  }
}
