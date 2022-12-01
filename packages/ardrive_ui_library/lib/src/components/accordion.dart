import 'package:flutter/material.dart';

typedef ExpansionPanelHeaderBuilder = Widget Function(
  BuildContext context,
  bool isExpanded,
);

typedef ArDriveAccordionEntry = MapEntry<ExpansionPanelHeaderBuilder, Widget>;

class ArDriveAccordion extends StatefulWidget {
  final List<ArDriveAccordionEntry> children;
  const ArDriveAccordion({
    Key? key,
    required this.children,
  }) : super(key: key);

  @override
  State<ArDriveAccordion> createState() => _ArDriveAccordionState();
}

class _ArDriveAccordionState extends State<ArDriveAccordion> {
  @override
  Widget build(BuildContext context) {
    return ExpansionPanelList(
      children: [
        ...widget.children.map(
          (child) => ExpansionPanel(
            headerBuilder: child.key,
            body: child.value,
          ),
        )
      ],
    );
  }
}
