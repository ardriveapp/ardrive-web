import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

typedef ArDriveTab = MapEntry<Tab, Widget>;

class ArDriveTabView extends StatefulWidget {
  final List<ArDriveTab> tabs;
  final Color? backgroundColor;
  final Color? selectedLabelColor;
  final Color? unselectedLabelColor;
  final Color? selectedTabColor;
  final Color? unselectedTabColor;

  const ArDriveTabView({
    Key? key,
    required this.tabs,
    this.backgroundColor,
    this.selectedLabelColor,
    this.unselectedLabelColor,
    this.selectedTabColor,
    this.unselectedTabColor,
  }) : super(key: key);

  @override
  State<ArDriveTabView> createState() => _ArDriveTabViewState();
}

class _ArDriveTabViewState extends State<ArDriveTabView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(vsync: this, length: widget.tabs.length);
    _tabController.addListener(() {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ArDriveTabBar(
          tabs: [...widget.tabs.map((tab) => tab.key)],
          controller: _tabController,
          selectedLabelColor: widget.selectedLabelColor,
          unselectedLabelColor: widget.unselectedLabelColor,
          selectedTabColor: widget.selectedTabColor,
          unselectedTabColor: widget.unselectedTabColor,
        ),
        const SizedBox(
          height: 28,
        ),
        Expanded(
          child: ArDriveCard(
            contentPadding: EdgeInsets.zero,
            backgroundColor: widget.backgroundColor ??
                ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
            content: TabBarView(
              controller: _tabController,
              children: [...widget.tabs.map((tab) => tab.value)],
            ),
          ),
        )
      ],
    );
  }
}

class ArDriveTabBar extends StatelessWidget {
  final List<Tab> tabs;
  final TabController controller;
  final Color? selectedTabColor;
  final Color? unselectedTabColor;
  final Color? selectedLabelColor;
  final Color? unselectedLabelColor;

  const ArDriveTabBar({
    super.key,
    required this.tabs,
    required this.controller,
    this.selectedTabColor,
    this.unselectedTabColor,
    this.selectedLabelColor,
    this.unselectedLabelColor,
  });

  final borderRadius = 8.0;

  BorderRadius calculateBorderRadius(int tabIndex, noOfTabs) {
    if (tabIndex == 0) {
      return BorderRadius.only(
        topLeft: Radius.circular(borderRadius),
        bottomLeft: Radius.circular(borderRadius),
      );
    } else if (tabIndex == noOfTabs - 1) {
      return BorderRadius.only(
        topRight: Radius.circular(borderRadius),
        bottomRight: Radius.circular(borderRadius),
      );
    } else {
      return BorderRadius.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: unselectedTabColor ??
            ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          borderRadius: calculateBorderRadius(
            controller.index,
            controller.length,
          ),
          color: selectedTabColor ??
              ArDriveTheme.of(context).themeData.tableTheme.selectedItemColor,
        ),
        labelColor: selectedLabelColor ??
            ArDriveTheme.of(context).themeData.colors.themeFgDefault,
        unselectedLabelColor: unselectedLabelColor ??
            ArDriveTheme.of(context).themeData.colors.themeAccentDisabled,
        tabs: tabs,
      ),
    );
  }
}
