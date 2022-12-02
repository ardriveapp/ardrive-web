import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory accordion() {
  return WidgetbookCategory(name: 'Accordion', widgets: [
    WidgetbookComponent(name: 'Accordion ', useCases: [
      WidgetbookUseCase(
          name: 'With content',
          builder: (context) {
            return ArDriveStorybookAppBase(
              builder: (context) => _accordionWithContent(),
            );
          }),
    ]),
  ]);
}

class Item {
  Item({
    required this.expandedValue,
    required this.headerValue,
    this.isExpanded = false,
  });

  String expandedValue;
  String headerValue;
  bool isExpanded;
}

List<Item> generateItems(int numberOfItems) {
  return List<Item>.generate(numberOfItems, (int index) {
    return Item(
      headerValue: 'Panel $index',
      expandedValue: 'This is item number $index',
    );
  });
}

Widget _accordionWithContent() {
  final List<Item> data = generateItems(8);

  return ArDriveAccordion(
    children: data
        .map(
          (item) => ArDriveAccordionItem(
            ListTile(
              title: Text(item.headerValue),
            ),
            [
              ListTile(
                title: Text(item.expandedValue),
                subtitle: const Text('Subtitle Lorem Ipsum'),
                onTap: () {},
              )
            ],
          ),
        )
        .toList(),
  );
}
