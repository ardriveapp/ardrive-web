import 'package:flutter/material.dart';
import 'package:storybook/src/accordion.dart';
import 'package:storybook/src/button.dart';
import 'package:storybook/src/card.dart';
import 'package:storybook/src/checkbox.dart';
import 'package:storybook/src/click_area.dart';
import 'package:storybook/src/colors.dart';
import 'package:storybook/src/fab.dart';
import 'package:storybook/src/icons.dart';
import 'package:storybook/src/image.dart';
import 'package:storybook/src/modals.dart';
import 'package:storybook/src/overlay.dart';
import 'package:storybook/src/progress_bar.dart';
import 'package:storybook/src/shadows.dart';
import 'package:storybook/src/tab_view.dart';
import 'package:storybook/src/table.dart';
import 'package:storybook/src/text_field.dart';
import 'package:storybook/src/toggle.dart';
import 'package:widgetbook/widgetbook.dart';

class StoryBook extends StatelessWidget {
  const StoryBook({super.key});

  @override
  Widget build(BuildContext context) {
    final devices = [
      Apple.iPhone12,
      Apple.iPhone13,
      Apple.macBook14Inch,
      Apple.iMacRetina27Inch,
      Desktop.desktop1080p,
      Desktop.desktop1440p,
      Desktop.desktop4k,
    ];

    return Widgetbook.material(
      directories: [
        WidgetbookCategory(
          name: 'Default',
          children: [
            toggle(),
            textField(),
            getColors(),
            shadows(),
            button(),
            card(),
            table(),
            modals(),
            tabView(),
            progressBar(),
            overlay(),
            accordion(),
            image(),
            checkBox(),
            fab(),
            clickArea(),
            icons(),
          ],
        )
      ],
      addons: [
        DeviceAddon(
            setting: DeviceSetting(
          devices: devices,
          activeDevice: devices.first,
        )),
      ],
    );
  }
}
