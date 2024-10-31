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
  final bool automaticallyCloseWhenOpenAnotherItem;

  const ArDriveAccordion({
    super.key,
    required this.children,
    this.backgroundColor,
    this.contentPadding,
    this.automaticallyCloseWhenOpenAnotherItem = false,
  });

  @override
  State<ArDriveAccordion> createState() => _ArDriveAccordionState();
}

class _ArDriveAccordionState extends State<ArDriveAccordion> {
  late List<ArDriveAccordionItem> tiles;
  late List<ExpansionTileController> controller;

  @override
  void initState() {
    tiles = [...widget.children];
    controller =
        List.generate(tiles.length, (index) => ExpansionTileController());
    super.initState();
  }

  @override
  void didUpdateWidget(ArDriveAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);

    tiles = [...widget.children];
    controller =
        List.generate(tiles.length, (index) => ExpansionTileController());
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
                if (widget.automaticallyCloseWhenOpenAnotherItem) {
                  for (var i = 0; i < tiles.length; i++) {
                    if (tiles[i] != tile) {
                      controller[i].collapse();
                    }
                  }
                }
                if (value) controller[index].expand();
                setState(() => tiles[tiles.indexOf(tile)].isExpanded = !value);
              },
              maintainState: false,
              controller: controller[index],
              children: tile.children,
            ),
          );
        },
      ),
    );
  }
}
