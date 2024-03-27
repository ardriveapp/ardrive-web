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
  });

  final Widget child;
  final List<Widget> menuChildren;
  final MenuController? parentMenuController;
  final MenuController menuController;
  final Function? onClick;
  final Offset alignmentOffset;
  final bool isDisabled;

  @override
  State<ArDriveMenuWidget> createState() => _ArDriveMenuWidgetState();
}

class _ArDriveMenuWidgetState extends State<ArDriveMenuWidget> {
  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: widget.alignmentOffset,
      controller: widget.menuController,
      menuChildren: widget.menuChildren,
      child: GestureDetector(
        onTap: () {
          if (!widget.isDisabled) {
            widget.onClick?.call();
          }
        },
        child: ArDriveClickArea(
          showCursor: !widget.isDisabled,
          child: widget.child,
        ),
      ),
    );
  }
}
