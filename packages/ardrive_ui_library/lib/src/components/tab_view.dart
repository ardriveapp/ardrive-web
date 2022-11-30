import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';

class ArDriveTabView extends StatefulWidget {
  final List<Tab> tabs;
  final List<Widget> children;
  const ArDriveTabView({Key? key, required this.tabs, required this.children})
      : super(key: key);

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
    return ArDriveCard(
      backgroundColor: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
      content: Column(
        children: [
          ArDriveTabBar(
            tabs: widget.tabs,
            controller: _tabController,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: widget.children,
            ),
          )
        ],
      ),
    );
  }
}

class ArDriveTabBar extends StatelessWidget {
  final List<Tab> tabs;
  final TabController controller;

  const ArDriveTabBar(
      {super.key, required this.tabs, required this.controller});

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
      height: 45,
      decoration: BoxDecoration(
        color: ArDriveTheme.of(context).themeData.colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          borderRadius: calculateBorderRadius(
            controller.index,
            controller.length,
          ),
          color: ArDriveTheme.of(context).themeData.colors.themeGbMuted,
        ),
        labelColor: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
        unselectedLabelColor:
            ArDriveTheme.of(context).themeData.colors.themeAccentDisabled,
        tabs: tabs,
      ),
    );
  }
}
