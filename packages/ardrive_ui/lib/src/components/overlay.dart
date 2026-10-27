import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_portal/flutter_portal.dart';

export 'package:flutter_portal/flutter_portal.dart'
    show Anchor, Aligned, AxisFlag, Filled;

class ArDriveDropdown extends StatefulWidget {
  const ArDriveDropdown({
    super.key,
    required this.items,
    required this.child,
    this.contentPadding,
    this.height = 48,
    this.anchor = const Aligned(
      follower: Alignment.topLeft,
      target: Alignment.bottomLeft,
      offset: Offset(0, 4),
    ),
    this.dividerThickness,
    this.calculateVerticalAlignment,
    this.maxHeight,
    this.showScrollbars = false,
    this.onClick,
    this.hasDivider = true,
    this.hasBorder = true,
    this.header,
  });

  final double height;
  final List<ArDriveDropdownItem> items;
  final Widget child;
  final EdgeInsets? contentPadding;
  final double? dividerThickness;
  final Anchor anchor;
  final double? maxHeight;
  final bool showScrollbars;
  final Function? onClick;
  final bool hasDivider;
  final bool hasBorder;

  /// Sits above the items and outside their hover wrapper, for a menu that
  /// needs to state something rather than offer it. It does not highlight like
  /// an action; it is still dismissed by the overlay's barrier like the rest of
  /// the menu.
  final Widget? header;

  /// The menu's follower alignment, given whether it opens up: in the lower
  /// half of the screen, or when it fits better above (see `_placeMenu`).
  final Alignment Function(bool)? calculateVerticalAlignment;

  @override
  State<ArDriveDropdown> createState() => _ArDriveDropdownState();
}

class _ArDriveDropdownState extends State<ArDriveDropdown> {
  bool visible = false;
  late Anchor _anchor;

  double dropdownHeight = 0;

  @override
  void initState() {
    _anchor = widget.anchor;

    super.initState();
  }

  /// The menu's height once [_placeMenu] fitted it to the screen, when the
  /// whole of it fits on neither side of its button.
  double? _fittedHeight;

  @override
  void didChangeDependencies() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && visible) setState(_placeMenu);
    });

    super.didChangeDependencies();
  }

  /// Chooses whether the menu opens up or down from where its button is now,
  /// not where it was first laid out: up in the lower half of the screen, as
  /// before, and also from higher up when the menu would run off the bottom
  /// and there is more room above. When it fits on neither side, it takes the
  /// roomier one and scrolls, so every item stays in reach.
  void _placeMenu() {
    final calculate = widget.calculateVerticalAlignment;
    if (calculate == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final top = renderBox.localToGlobal(Offset.zero).dy;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // The menu's near edge sits at the anchor's target point, not at the
    // button's top: a menu hanging from the button's bottom has that much
    // less room below.
    final base = widget.anchor;
    final anchorY = base is Aligned
        ? top + renderBox.size.height * (base.target.y + 1) / 2 + base.offset.dy
        : top + renderBox.size.height;
    final roomBelow = screenHeight - anchorY - _screenMargin;
    final roomAbove = anchorY - _screenMargin;
    final menuHeight = dropdownHeight;

    final opensUp = top > screenHeight / 2 ||
        (menuHeight > roomBelow && roomAbove > roomBelow);
    final room = opensUp ? roomAbove : roomBelow;
    _fittedHeight = menuHeight > room && room > 0 ? room : null;

    final alignment = calculate(opensUp);

    // Only the follower is the calculation's to decide. Everything else
    // belongs to the caller and used to be discarded with it: a menu that
    // asked to hang from its button's bottom-*right*, and to be shifted
    // back inside the screen, got neither - it was re-anchored to
    // bottom-left with no shifting, and on a 320px phone it opened 51px
    // off the left edge with every item's icon outside the viewport.
    _anchor = base is Aligned
        ? Aligned(
            follower: alignment,
            target: base.target,
            offset: base.offset,
            widthFactor: base.widthFactor,
            heightFactor: base.heightFactor,
            shiftToWithinBound: base.shiftToWithinBound,
            backup: base.backup,
          )
        : Aligned(
            follower: alignment,
            target: Alignment.bottomLeft,
          );
  }

  /// Kept clear between a placed menu and the screen's edge.
  static const _screenMargin = 8.0;

  @override
  Widget build(BuildContext context) {
    // The rows grow with the reader's text scale (see ArDriveDropdownItemTile),
    // so the box that holds them has to as well or it clips them.
    dropdownHeight = widget.maxHeight ??
        widget.items.length *
            widget.height *
            MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);

    final dropdownTheme = ArDriveTheme.of(context).themeData.dropdownTheme;

    // An open menu is placed again when the window changes size. Only an
    // open one depends on it, so closed rows don't rebuild on a resize.
    if (visible) MediaQuery.sizeOf(context);

    return ArDriveOverlay(
      onVisibleChange: (value) {
        setState(() {
          visible = value;
        });
      },
      visible: visible,
      anchor: _anchor,
      content: _ArDriveDropdownContent(
        height: _fittedHeight ?? dropdownHeight,
        child: ArDriveCard(
          border: widget.hasBorder
              ? Border.all(
                  color: ArDriveTheme.of(context)
                      .themeData
                      .dropdownTheme
                      .backgroundColor,
                  width: 1,
                )
              : null,
          boxShadow: BoxShadowCard.shadow80,
          elevation: 5,
          contentPadding: widget.contentPadding ?? EdgeInsets.zero,
          content: SingleChildScrollView(
            child: Container(
              color: ArDriveTheme.of(context)
                  .themeData
                  .dropdownTheme
                  .backgroundColor,
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    if (widget.header != null) widget.header!,
                    Column(
                      children: List.generate(widget.items.length, (index) {
                        // A button of its own, named by its text, and
                        // disabled when it has nothing to do: without the
                        // flag the web gave it no role and no name.
                        return Semantics(
                          container: true,
                          button: true,
                          enabled: widget.items[index].onClick != null,
                          child: GestureDetector(
                            onTap: () {
                              widget.items[index].onClick?.call();
                              setState(() {
                                visible = !visible;
                              });
                            },
                            child: ArDriveHoverWidget(
                              hoverColor: dropdownTheme.hoverColor,
                              defaultColor: dropdownTheme.backgroundColor,
                              child: Row(
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  // Expanded, so the item is laid out to the
                                  // menu's width. A Row hands its non-flexible
                                  // children an unbounded main axis, so an item
                                  // used to measure itself at whatever width its
                                  // longest word wanted and the menu overflowed
                                  // by the difference - which on a 320px phone
                                  // at text scale 2.0 was 58 pixels off the
                                  // right edge of every menu in the app. A
                                  // bounded width is also what lets a label
                                  // inside the item give at all.
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [widget.items[index]],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          widget.onClick?.call();
          setState(() {
            visible = !visible;
            if (visible) _placeMenu();
          });
        },
        child: IgnorePointer(ignoring: visible, child: widget.child),
      ),
    );
  }
}

class _ArDriveDropdownContent extends StatefulWidget {
  @override
  _ArDriveDropdownContentState createState() => _ArDriveDropdownContentState();

  const _ArDriveDropdownContent({
    required this.child,
    this.height = 200,
  });

  final Widget child;
  final double height;
}

class _ArDriveDropdownContentState extends State<_ArDriveDropdownContent>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = Tween<double>(begin: 0, end: widget.height)
        .animate(_animationController);
    _animationController.forward();
  }

  @override
  void didUpdateWidget(covariant _ArDriveDropdownContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fitted again to a resized window: the open menu takes the new height.
    if (widget.height != oldWidget.height) {
      _animation = Tween<double>(begin: 0, end: widget.height)
          .animate(_animationController);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return ArDriveScrollBar(
          isVisible: false,
          child: SingleChildScrollView(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                double maxHeight = constraints.maxHeight;
                double currentHeight = _animation.value.clamp(0.0, maxHeight);
                return SizedBox(
                  height: currentHeight,
                  child: child,
                );
              },
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

class ArDriveOverlay extends StatefulWidget {
  const ArDriveOverlay({
    super.key,
    required this.content,
    this.contentPadding = const EdgeInsets.all(16),
    required this.child,
    required this.anchor,
    this.visible,
    this.onVisibleChange,
    this.closeOnBarrierTap = true,
  });

  final Widget child;
  final Widget content;
  final EdgeInsets contentPadding;
  final Anchor anchor;
  final bool? visible;
  final Function(bool)? onVisibleChange;
  final bool closeOnBarrierTap;
  @override
  State<ArDriveOverlay> createState() => _ArDriveOverlayState();
}

class _ArDriveOverlayState extends State<ArDriveOverlay> {
  @override
  void initState() {
    super.initState();
    _visible = widget.visible ?? false;
    _updateVisibleState();
  }

  @override
  void didUpdateWidget(oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      setState(() {
        _updateVisibleState();
      });
    }
  }

  void _updateVisibleState() {
    if (widget.visible != null) {
      _visible = widget.visible!;
    } else {
      _visible = false;
    }
  }

  late bool _visible;

  @override
  Widget build(BuildContext context) {
    if (widget.closeOnBarrierTap) {
      return Barrier(
        onClose: () {
          setState(() {
            _visible = !_visible;
            widget.onVisibleChange?.call(_visible);
          });
        },
        visible: _visible,
        child: PortalTarget(
          anchor: widget.anchor,
          portalFollower: widget.content,
          visible: _visible,
          child: widget.child,
        ),
      );
    }

    return PortalTarget(
      anchor: widget.anchor,
      portalFollower: widget.content,
      visible: _visible,
      child: widget.child,
    );
  }
}

/// Closes what it covers on a click anywhere else, or on Escape.
class Barrier extends StatefulWidget {
  const Barrier({
    super.key,
    required this.onClose,
    required this.visible,
    required this.child,
  });

  final Widget child;
  final VoidCallback onClose;
  final bool visible;

  @override
  State<Barrier> createState() => _BarrierState();
}

class _BarrierState extends State<Barrier> {
  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void didUpdateWidget(Barrier oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        HardwareKeyboard.instance.addHandler(_onKey);
      } else {
        HardwareKeyboard.instance.removeHandler(_onKey);
      }
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// The way out for a keyboard, and for a screen reader, which has no
  /// barrier to press: see below.
  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PortalTarget(
      visible: widget.visible,
      closeDuration: kThemeAnimationDuration,
      // Out of the accessibility tree. It covers the whole screen and comes
      // after what it covers, so with the tree on the browser put it on top:
      // every click on a menu item or a link in the card landed on it, and
      // only closed what was open.
      portalFollower: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
        ),
      ),
      child: widget.child,
    );
  }
}

class ArDriveDropdownItem extends StatefulWidget {
  const ArDriveDropdownItem({
    super.key,
    required this.content,
    this.onClick,
  });

  final Widget content;
  final Function()? onClick;

  @override
  State<ArDriveDropdownItem> createState() => _ArDriveDropdownItemState();
}

class _ArDriveDropdownItemState extends State<ArDriveDropdownItem> {
  bool hovering = false;
  @override
  Widget build(BuildContext context) {
    return widget.content;
  }
}

class ArDriveHoverWidget extends StatefulWidget {
  const ArDriveHoverWidget({
    super.key,
    required this.child,
    this.showMouseCursor = true,
    required this.hoverColor,
    required this.defaultColor,
  });

  final Widget child;
  final bool showMouseCursor;
  final Color? hoverColor;
  final Color? defaultColor;

  @override
  State<ArDriveHoverWidget> createState() => _ArDriveHoverWidgetState();
}

class _ArDriveHoverWidgetState extends State<ArDriveHoverWidget> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.showMouseCursor
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onHover: (event) {
        if (widget.showMouseCursor) {
          setState(() {
            hovering = true;
          });
        }
      },
      onExit: (event) {
        if (widget.showMouseCursor) {
          setState(() {
            hovering = false;
          });
        }
      },
      child: Container(
        color: hovering ? widget.hoverColor : widget.defaultColor,
        child: widget.child,
      ),
    );
  }
}
