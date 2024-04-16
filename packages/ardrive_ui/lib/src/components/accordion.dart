import 'package:ardrive_ui/ardrive_ui.dart';
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
  final Color? backgroundColor;
  final EdgeInsetsGeometry? contentPadding;

  const ArDriveAccordion({
    Key? key,
    required this.children,
    this.backgroundColor,
    this.contentPadding,
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
      child: ListView.builder(
        padding: EdgeInsets.zero,
        key: widget.key,
        shrinkWrap: true,
        itemCount: tiles.length,
        itemBuilder: (context, index) {
          final tile = tiles[index];

          return ExpansionTileTheme(
            data: ExpansionTileThemeData(
              backgroundColor: widget.backgroundColor ??
                  ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
              collapsedBackgroundColor: widget.backgroundColor ??
                  ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
              collapsedIconColor:
                  ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              textColor:
                  ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              collapsedTextColor:
                  ArDriveTheme.of(context).themeData.colors.themeFgDefault,
              iconColor:
                  ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
            child: ExpansionTile(
              title: tile.title,
              initiallyExpanded: tile.isExpanded,
              expandedAlignment: Alignment.centerLeft,
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              onExpansionChanged: (value) {
                setState(() => tiles[tiles.indexOf(tile)].isExpanded = !value);
              },
              children: tile.children,
            ),
          );
        },
      ),
    );
  }
}
