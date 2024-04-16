import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory accordion() {
  return WidgetbookCategory(name: 'Accordion', children: [
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

List<Text> generateItems(int numberOfItems) {
  return List<Text>.generate(numberOfItems, (int index) {
    return Text('This is item number $index');
  });
}

Widget _accordionWithContent() {
  final List<Text> data = generateItems(3);

  return ArDriveAccordion(
    children: [1, 2]
        .map(
          (item) => ArDriveAccordionItem(
            isExpanded: true,
            ListTile(
              title: Text(
                'Drive $item',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  children: data
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.all(4),
                          child: e,
                        ),
                      )
                      .toList(),
                ),
              )
            ],
          ),
        )
        .toList(),
  );
}
