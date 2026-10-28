import 'dart:math' as math;

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class ArDriveSubmenuItem {
  final Widget widget;
  final List<ArDriveSubmenuItem>? children;
  final Function? onClick;
  final bool isDisabled;

  ArDriveSubmenuItem({
    required this.widget,
    this.children,
    this.onClick,
    this.isDisabled = false,
  });
}

/// A menu that opens from [child], and items in it that open menus of their
/// own beside them.
///
/// Drawn and placed as Material's MenuAnchor did, but in the navigator's
/// overlay through [ArDriveOverlay], so that with the browser's accessibility
/// tree on a click on an item lands on the item rather than on the page
/// behind it. A click outside closes it and still reaches what it lands on;
/// Escape closes it too.
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
  bool _open = false;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      setState(() => _open = true);
      widget.onOpen?.call();
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveOverlay(
      visible: _open,
      onVisibleChange: (visible) {
        if (!visible) _close();
      },
      closeOnBarrierTap: false,
      closeOnEscape: true,
      anchor: _MenuPlacement(
        alignment: Alignment.bottomLeft,
        alignmentOffset: widget.alignmentOffset,
        parentOrientation: Axis.horizontal,
      ),
      content: TapRegion(
        groupId: this,
        onTapOutside: (_) => _close(),
        child: _MenuPanel(
          items: widget.menuChildren,
          groupId: this,
          closeAll: _close,
        ),
      ),
      // What opens the menu is the caller's own button, which names itself.
      child: TapRegion(
        groupId: this,
        child: GestureDetector(
          onTap: _toggle,
          child: ArDriveClickArea(child: widget.child),
        ),
      ),
    );
  }
}

/// The menu itself: Material's menu panel, which MenuAnchor drew.
class _MenuPanel extends StatelessWidget {
  const _MenuPanel({
    required this.items,
    required this.groupId,
    required this.closeAll,
  });

  final List<ArDriveSubmenuItem> items;
  final Object groupId;
  final VoidCallback closeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // MenuAnchor's padding, 8 above and below, less the visual density: none
    // on a desktop browser, where the density is compact.
    final density = theme.visualDensity.baseSizeAdjustment;
    final padding = EdgeInsets.symmetric(
      horizontal: math.max(0, density.dx),
      vertical: math.max(0, 8 + density.dy),
    );

    return IntrinsicWidth(
      child: Material(
        elevation: 3,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        color: theme.colorScheme.surface,
        shadowColor: theme.colorScheme.shadow,
        child: Padding(
          padding: padding,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in items)
                  item.children == null
                      ? _MenuItem(item: item, closeAll: closeAll)
                      : _SubmenuItem(
                          item: item,
                          groupId: groupId,
                          closeAll: closeAll,
                        ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An item that does something, then closes the whole menu.
class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.item, required this.closeAll});

  final ArDriveSubmenuItem item;
  final VoidCallback closeAll;

  @override
  Widget build(BuildContext context) {
    final target = GestureDetector(
      onTap: () {
        if (item.isDisabled) return;
        item.onClick?.call();
        closeAll();
      },
      child: ArDriveClickArea(
        showCursor: !item.isDisabled,
        child: item.widget,
      ),
    );

    // A row with nothing to do, such as a divider, is not a button.
    if (item.onClick == null) return target;

    // A button of its own, named by its text: without the flag the web gave
    // the item no role and no name.
    return Semantics(
      container: true,
      button: true,
      enabled: !item.isDisabled,
      child: target,
    );
  }
}

/// An item that opens a menu of its own beside it.
class _SubmenuItem extends StatefulWidget {
  const _SubmenuItem({
    required this.item,
    required this.groupId,
    required this.closeAll,
  });

  final ArDriveSubmenuItem item;
  final Object groupId;
  final VoidCallback closeAll;

  @override
  State<_SubmenuItem> createState() => _SubmenuItemState();
}

class _SubmenuItemState extends State<_SubmenuItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return ArDriveOverlay(
      visible: _open,
      // The menu it opens from has the click-outside and Escape handling.
      closeOnBarrierTap: false,
      anchor: const _MenuPlacement(
        alignment: Alignment.topRight,
        parentOrientation: Axis.vertical,
      ),
      content: TapRegion(
        groupId: widget.groupId,
        child: _MenuPanel(
          items: item.children!,
          groupId: widget.groupId,
          closeAll: widget.closeAll,
        ),
      ),
      child: Semantics(
        container: true,
        button: true,
        enabled: !item.isDisabled,
        child: GestureDetector(
          onTap: () {
            if (item.isDisabled) return;
            setState(() => _open = !_open);
          },
          child: ArDriveClickArea(
            showCursor: !item.isDisabled,
            child: ArDriveClickArea(child: item.widget),
          ),
        ),
      ),
    );
  }
}

/// Where Material's MenuAnchor put a menu, as an [Anchor]: [alignment] on
/// the button plus [alignmentOffset], moved to the other side of the button
/// when it would leave the screen, and otherwise pushed back onto it. Its
/// size stays 8px inside the screen's edges.
@immutable
class _MenuPlacement implements Anchor {
  const _MenuPlacement({
    required this.alignment,
    this.alignmentOffset = Offset.zero,
    required this.parentOrientation,
  });

  final Alignment alignment;
  final Offset alignmentOffset;

  /// Horizontal for a menu that opens from a button, vertical for one that
  /// opens from an item in another menu. Only the first moves its offset
  /// with it when it flips above the button.
  final Axis parentOrientation;

  static const _screenMargin = 8.0;

  @override
  BoxConstraints getFollowerConstraints({
    required Size targetSize,
    required BoxConstraints theaterConstraints,
  }) {
    return BoxConstraints.loose(theaterConstraints.biggest)
        .deflate(const EdgeInsets.all(_screenMargin));
  }

  @override
  Offset getFollowerOffset({
    required Size followerSize,
    required Size targetSize,
    required Rect theaterRect,
  }) {
    // In the target's coordinates, as the anchor works: the button is at the
    // origin and the screen is theaterRect.
    final anchorRect = Offset.zero & targetSize;
    final allowed = theaterRect;
    final desired = alignment.withinRect(anchorRect) + alignmentOffset;
    var x = desired.dx;
    var y = desired.dy;

    bool offLeft(double x) => x < allowed.left;
    bool offRight(double x) => x + followerSize.width > allowed.right;
    bool offTop(double y) => y < allowed.top;
    bool offBottom(double y) => y + followerSize.height > allowed.bottom;

    // The menu is a vertical list, so a menu opening from a horizontal parent
    // has a different orientation from it and is pushed rather than flipped.
    final flipsSideways = parentOrientation == Axis.vertical;

    if (followerSize.width >= allowed.width) {
      x = allowed.left;
    } else if (offLeft(x)) {
      final newX = anchorRect.right + alignmentOffset.dx;
      x = flipsSideways && !offRight(newX) ? newX : allowed.left;
    } else if (offRight(x)) {
      final newX = anchorRect.left - followerSize.width - alignmentOffset.dx;
      x = flipsSideways && !offLeft(newX)
          ? newX
          : allowed.right - followerSize.width;
    }

    if (followerSize.height >= allowed.height) {
      y = allowed.top;
    } else if (offTop(y)) {
      final newY = anchorRect.bottom;
      y = !offBottom(newY) ? newY : allowed.top;
    } else if (offBottom(y)) {
      final newY = anchorRect.top - followerSize.height;
      if (!offTop(newY)) {
        y = parentOrientation == Axis.horizontal
            ? newY - alignmentOffset.dy
            : newY;
      } else {
        y = allowed.bottom - followerSize.height;
      }
    }
    return Offset(x, y);
  }
}
