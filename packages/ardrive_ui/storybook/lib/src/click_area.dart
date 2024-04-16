import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory clickArea() {
  return WidgetbookCategory(
    name: 'Click Area',
    children: [
      WidgetbookComponent(
        name: 'Click Area',
        useCases: [
          WidgetbookUseCase(
            name: 'Default',
            builder: (context) {
              return Center(
                child: ArDriveClickArea(
                  child: Container(
                    width: 200,
                    height: 200,
                    color: Colors.red,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ],
  );
}
