import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';

typedef ExpansionPanelHeaderBuilder = Widget Function(
  BuildContext context,
  bool isExpanded,
);

class ArDriveAccordionItem {
  final Widget title;
  final List<Widget> children;
  bool isExpanded;

  ArDriveAccordionItem(
    this.title,
    this.children, {
    this.isExpanded = false,
  });
}

class ArDriveAccordion extends StatefulWidget {
  final List<ArDriveAccordionItem> children;
  const ArDriveAccordion({
    Key? key,
    required this.children,
  }) : super(key: key);

  @override
  State<ArDriveAccordion> createState() => _ArDriveAccordionState();
}

class _ArDriveAccordionState extends State<ArDriveAccordion> {
  late List<ArDriveAccordionItem> tiles;
  @override
  void initState() {
    tiles = [...widget.children];
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ListView(
        children: tiles.map(
          (tile) {
            return ExpansionTileTheme(
              data: ExpansionTileThemeData(
                backgroundColor:
                    ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
                collapsedBackgroundColor:
                    ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
                collapsedIconColor:
                    ArDriveTheme.of(context).themeData.colors.themeAccentBrand,
                textColor:
                    ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                collapsedTextColor:
                    ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              ),
              child: ExpansionTile(
                title: tile.title,
                children: tile.children,
                onExpansionChanged: (value) {
                  setState(
                      () => tiles[tiles.indexOf(tile)].isExpanded = !value);
                },
              ),
            );
          },
        ).toList(),
      ),
    );
  }
}
