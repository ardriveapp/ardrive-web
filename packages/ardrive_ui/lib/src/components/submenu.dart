import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class ArDriveSubmenuItem {
  final Widget widget;
  final List<ArDriveSubmenuItem>? children;
  final Function? onClick;
  final MenuController menuController = MenuController();
  final bool isDisabled;

  ArDriveSubmenuItem({
    required this.widget,
    this.children,
    this.onClick,
    this.isDisabled = false,
  });
}

class ArDriveSubmenu extends StatefulWidget {
  const ArDriveSubmenu({
    super.key,
    required this.child,
    required this.menuChildren,
    this.alignmentOffset = Offset.zero,
    this.onOpen,
    this.onClose,
  });

  final Widget child;
  final List<ArDriveSubmenuItem> menuChildren;
  final Offset alignmentOffset;
  final Function? onOpen;
  final Function? onClose;

  @override
  State<ArDriveSubmenu> createState() => _ArDriveSubmenuState();
}

class _ArDriveSubmenuState extends State<ArDriveSubmenu> {
  final topMenuController = MenuController();

  @override
  Widget build(BuildContext context) {
    return ArDriveMenuWidget(
      onClick: () {
        if (topMenuController.isOpen) {
          topMenuController.close();
          widget.onClose?.call();
        } else {
          topMenuController.open();
          widget.onOpen?.call();
        }
      },
      menuController: topMenuController,
      menuChildren: _buildMenu(widget.menuChildren),
      alignmentOffset: widget.alignmentOffset,
      // What opens the menu is the caller's own button, which names itself.
      isMenuItem: false,
      child: widget.child,
    );
  }

  List<Widget> _buildMenu(List<ArDriveSubmenuItem> menuChildren) {
    List<Widget> children = [];

    for (final element in menuChildren) {
      if (element.children == null) {
        children.add(
          ArDriveMenuWidget(
            isDisabled: element.isDisabled,
            // A row with nothing to do, such as a divider, is not a button.
            isMenuItem: element.onClick != null,
            onClick: () {
              element.onClick?.call();
              topMenuController.close();
            },
            parentMenuController: topMenuController,
            menuController: element.menuController,
            menuChildren: const [],
            child: element.widget,
          ),
        );
        continue;
      }
      children.add(_buildMenuItem(element, element.menuController));
    }
    return children;
  }

  Widget _buildMenuItem(
      ArDriveSubmenuItem item, MenuController parentMenuController) {
    return ArDriveMenuWidget(
      isDisabled: item.isDisabled,
      onClick: () {
        if (item.children == null || item.children!.isEmpty) {
          item.onClick?.call();
        } else {
          if (item.menuController.isOpen) {
            item.menuController.close();
          } else {
            item.menuController.open();
          }
        }
      },
      parentMenuController: parentMenuController,
      menuController: item.menuController,
      menuChildren: item.children!.map((subMenuLeaf) {
        if (subMenuLeaf.children == null) {
          return ArDriveMenuWidget(
            isDisabled: subMenuLeaf.isDisabled,
            isMenuItem: subMenuLeaf.onClick != null,
            onClick: () {
              subMenuLeaf.onClick?.call();
              topMenuController.close();
            },
            parentMenuController: item.menuController,
            menuController: subMenuLeaf.menuController,
            menuChildren: const [],
            child: subMenuLeaf.widget,
          );
        }
        return _buildMenuItem(subMenuLeaf, subMenuLeaf.menuController);
      }).toList(),
      child: ArDriveClickArea(child: item.widget),
    );
  }
}

class ArDriveMenuWidget extends StatefulWidget {
  const ArDriveMenuWidget({
    super.key,
    required this.child,
    required this.menuChildren,
    this.parentMenuController,
    required this.menuController,
    this.onClick,
    this.alignmentOffset = Offset.zero,
    this.isDisabled = false,
    this.isMenuItem = true,
  });

  final Widget child;
  final List<Widget> menuChildren;
  final MenuController? parentMenuController;
  final MenuController menuController;
  final Function? onClick;
  final Offset alignmentOffset;
  final bool isDisabled;

  /// An item in a menu, rather than what opens one: only an item is made a
  /// button here. What opens a menu is usually a button already, and wrapping
  /// it again gave the screen reader an empty button around it.
  final bool isMenuItem;

  @override
  State<ArDriveMenuWidget> createState() => _ArDriveMenuWidgetState();
}

class _ArDriveMenuWidgetState extends State<ArDriveMenuWidget> {
  @override
  Widget build(BuildContext context) {
    final target = GestureDetector(
      onTap: () {
        if (!widget.isDisabled) {
          widget.onClick?.call();
        }
      },
      child: ArDriveClickArea(
        showCursor: !widget.isDisabled,
        child: widget.child,
      ),
    );

    return MenuAnchor(
      alignmentOffset: widget.alignmentOffset,
      controller: widget.menuController,
      menuChildren: widget.menuChildren,
      // A button of its own, named by its text: without the flag the web gave
      // the item no role and no name.
      child: widget.isMenuItem
          ? Semantics(
              container: true,
              button: true,
              enabled: !widget.isDisabled,
              child: target,
            )
          : target,
    );
  }
}
