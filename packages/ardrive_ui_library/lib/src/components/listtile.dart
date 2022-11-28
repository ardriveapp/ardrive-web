import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/container.dart';
import 'package:flutter/src/widgets/framework.dart';

class ArDriveListTile extends StatelessWidget {
  final Widget title;
  final bool selected;
  final void Function() onTap;
  const ArDriveListTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tileColor: ArDriveTheme.of(context).themeData.colors.themeBgSubtle,
        selectedColor:
            ArDriveTheme.of(context).themeData.colors.themeAccentBrand,
        selected: selected,
        onTap: onTap,
        title: title,
      ),
    );
  }
}
