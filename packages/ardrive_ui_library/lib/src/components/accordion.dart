import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';

typedef ExpansionPanelHeaderBuilder = Widget Function(
  BuildContext context,
  bool isExpanded,
);

class ArDriveAccordionItem {
  final ExpansionPanelHeaderBuilder headerBuilder;
  final Widget expandedBody;
  bool isExpanded;

  ArDriveAccordionItem(
    this.headerBuilder,
    this.expandedBody, {
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
  late List<ArDriveAccordionItem> panels;
  @override
  void initState() {
    panels = [...widget.children];
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
      child: SingleChildScrollView(
        child: ExpansionPanelList(
          dividerColor: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
          expansionCallback: (panelIndex, isExpanded) {
            setState(() {
              panels[panelIndex].isExpanded = !isExpanded;
            });
          },
          elevation: 0,
          expandedHeaderPadding: const EdgeInsets.all(0),
          children: [
            ...panels.map(
              (child) => ExpansionPanel(
                headerBuilder: child.headerBuilder,
                body: child.expandedBody,
                isExpanded: child.isExpanded,
                backgroundColor:
                    ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
              ),
            )
          ],
        ),
      ),
    );
  }
}
