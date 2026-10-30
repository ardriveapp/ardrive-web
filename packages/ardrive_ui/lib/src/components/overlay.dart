import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';

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
    // A menu hanging from its button's bottom that opens up hangs from the
    // button's top instead (below), so it has the room above the button.
    final hangsBelow = base is! Aligned || base.target.y > 0;
    final roomBelow = screenHeight - anchorY - _screenMargin;
    // Flipped, the offset is mirrored too: hanging 32 below becomes 32 above.
    final flippedTop =
        top - (base is Aligned && hangsBelow ? base.offset.dy : 0);
    final roomAbove = (hangsBelow ? flippedTop : anchorY) - _screenMargin;
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
    //
    // Opening up from a button's bottom, it takes the button's top edge (and
    // the mirrored offset): left on the bottom, the menu's lower edge sat on
    // the button's and covered it and whatever was beside it, such as the
    // Sync button under a drive's menu near the foot of the list.
    final flip = opensUp && hangsBelow;
    _anchor = base is Aligned
        ? Aligned(
            follower: alignment,
            target:
                flip ? Alignment(base.target.x, -base.target.y) : base.target,
            offset:
                flip ? Offset(base.offset.dx, -base.offset.dy) : base.offset,
            widthFactor: base.widthFactor,
            heightFactor: base.heightFactor,
            shiftToWithinBound: base.shiftToWithinBound,
            backup: base.backup,
          )
        : Aligned(
            follower: alignment,
            target: opensUp ? Alignment.topLeft : Alignment.bottomLeft,
          );
  }

  /// Kept clear between a placed menu and the screen's edge.
  static const _screenMargin = 8.0;

  @override
  Widget build(BuildContext context) {
    // The rows grow with the reader's text scale (see ArDriveDropdownItemTile),
    // so the box that holds them has to as well or it clips them.
    final dividers = widget.items.where((item) => item.isDivider).length;
    dropdownHeight = widget.maxHeight ??
        (widget.items.length - dividers) *
                widget.height *
                MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0) +
            dividers * ArDriveDropdownItem.dividerHeight;

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
                        if (widget.items[index].isDivider) {
                          return const _DropdownDivider();
                        }
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

/// Shows [content] next to [child], placed by [anchor], while [visible].
///
/// The content goes in an [OverlayEntry] in the navigator's overlay, after the
/// page, rather than in a portal under [child]. With the browser's
/// accessibility tree on, the web engine stacks semantics nodes in tree
/// order, and a portal's content sat in the tree where its button is: every
/// row and panel after the button was stacked on top of the menu, so a mouse
/// click on an item landed on what was behind it. In the overlay, the menu's
/// nodes come last and so lie on top.
///
/// The content is built in the overlay, so it can read what's provided above
/// the navigator but not a page's own providers; pass values in instead.
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
    this.closeOnEscape,
    this.barrierColor,
  });

  final Widget child;
  final Widget content;
  final EdgeInsets contentPadding;
  final Anchor anchor;
  final bool? visible;
  final Function(bool)? onVisibleChange;

  /// Whether a click anywhere else closes it, through a barrier that takes
  /// the click. Off for a menu that closes on its own terms, or a submenu
  /// inside a menu that already has one.
  final bool closeOnBarrierTap;

  /// Whether Escape closes it. Follows [closeOnBarrierTap] when not given.
  final bool? closeOnEscape;

  /// Fills the barrier behind the content: the scrim, for content that is a
  /// sheet over the page rather than a menu beside its button. Menus leave
  /// it clear.
  final Color? barrierColor;

  @override
  State<ArDriveOverlay> createState() => _ArDriveOverlayState();
}

class _ArDriveOverlayState extends State<ArDriveOverlay> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  late bool _visible;

  /// Whether another route, such as a dialog, is open over this one's page.
  /// The entry belongs to no route, so the navigator would leave it above
  /// the dialog, and its barrier would take the dialog's clicks: it goes
  /// offstage, keeping its state, until the page is on top again.
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    _visible = widget.visible ?? false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _covered = route != null && !route.isCurrent;
    _sync();
  }

  @override
  void didUpdateWidget(ArDriveOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      _visible = widget.visible ?? false;
    }
    _sync();
  }

  /// Shows or hides the entry to match. It is built in another part of the
  /// tree, which can't be marked dirty while this one builds, so it catches
  /// up after the frame. A closed menu with no entry has nothing to catch up.
  void _sync() {
    if (_visible || _entry != null) {
      _afterFrame(_visible ? _show : _hide);
    }
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _afterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
  }

  void _show() {
    final entry = _entry;
    if (entry != null) {
      entry.markNeedsBuild();
      return;
    }
    if (widget.closeOnEscape ?? widget.closeOnBarrierTap) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
    final newEntry = OverlayEntry(builder: _buildEntry);
    _entry = newEntry;
    Overlay.of(context).insert(newEntry);
  }

  void _hide() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _close() {
    setState(() => _visible = false);
    _hide();
    widget.onVisibleChange?.call(false);
  }

  /// The way out for a keyboard, and for a screen reader, which has no
  /// barrier to press.
  bool _onKey(KeyEvent event) {
    if (_covered) return false;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return true;
    }
    return false;
  }

  /// Where [ArDriveOverlay.child] is, in the overlay's coordinates.
  Rect? _targetRect() {
    final target = context.findRenderObject();
    final overlayBox = Overlay.of(context).context.findRenderObject();
    if (target is! RenderBox ||
        !target.hasSize ||
        !target.attached ||
        overlayBox is! RenderBox) {
      return null;
    }
    return target.localToGlobal(Offset.zero, ancestor: overlayBox) &
        target.size;
  }

  Widget _buildEntry(BuildContext overlayContext) {
    // Offstage while another route covers the page: not drawn, not clicked,
    // not read by a screen reader, and back as it was when the page returns.
    return Offstage(
      offstage: _covered,
      child: _buildLayers(),
    );
  }

  Widget _buildLayers() {
    return Stack(
      children: [
        if (widget.closeOnBarrierTap)
          // Out of the accessibility tree: it covers the whole screen, and
          // with the tree on the browser would put it over the menu.
          Positioned.fill(
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: widget.barrierColor == null
                    ? null
                    : ColoredBox(color: widget.barrierColor!),
              ),
            ),
          ),
        // Painted where the target is painted, so the menu moves with it when
        // the page scrolls; placed within that by the anchor.
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          child: _AnchoredFollower(
            anchor: widget.anchor,
            // Read here rather than while laying out, where another box's
            // size can't be read. A resize or a new text scale rebuilds the
            // entry, and the link above follows a scroll.
            target: _targetRect(),
            // Built in the overlay, the content would lose the text style,
            // icon theme and Material it had under its button: the themes
            // between the button and the overlay come with it, over a
            // transparent Material for ink and expansion tiles.
            child: Material(
              type: MaterialType.transparency,
              child: InheritedTheme.captureAll(
                context,
                widget.content,
                to: Overlay.of(context).context,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(link: _link, child: widget.child);
  }
}

/// Lays out its child by an [Anchor], relative to a target whose top-left is
/// this box's origin (the [CompositedTransformFollower] above puts it there).
class _AnchoredFollower extends SingleChildRenderObjectWidget {
  const _AnchoredFollower({
    required this.anchor,
    required this.target,
    required Widget child,
  }) : super(child: child);

  final Anchor anchor;

  /// Where the target is in the overlay; null before it has been laid out.
  final Rect? target;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnchoredFollower(anchor: anchor, target: target);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAnchoredFollower renderObject,
  ) {
    renderObject
      ..anchor = anchor
      ..target = target;
  }
}

class _RenderAnchoredFollower extends RenderShiftedBox {
  _RenderAnchoredFollower({
    required Anchor anchor,
    required Rect? target,
  })  : _anchor = anchor,
        _target = target,
        super(null);

  Anchor _anchor;
  set anchor(Anchor value) {
    if (value == _anchor) return;
    _anchor = value;
    markNeedsLayout();
  }

  Rect? _target;
  set target(Rect? value) {
    if (value == _target) return;
    _target = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    // As big as the overlay, which is the space the anchor places within.
    size = constraints.biggest;
    final child = this.child;
    if (child == null) return;

    final target = _target;
    final targetSize = target?.size ?? Size.zero;
    final targetTopLeft = target?.topLeft ?? Offset.zero;

    child.layout(
      _anchor.getFollowerConstraints(
        targetSize: targetSize,
        theaterConstraints: BoxConstraints.loose(size),
      ),
      parentUsesSize: true,
    );
    (child.parentData! as BoxParentData).offset = _anchor.getFollowerOffset(
      followerSize: child.size,
      targetSize: targetSize,
      // The overlay, relative to the target's top-left.
      theaterRect: (Offset.zero & size).shift(-targetTopLeft),
    );
  }

  // The menu can sit above or left of the target, outside this box's own
  // bounds, so a click is tested against the child alone.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);
}

class ArDriveDropdownItem extends StatefulWidget {
  const ArDriveDropdownItem({
    super.key,
    required this.content,
    this.onClick,
  }) : isDivider = false;

  /// A line between two groups of items. Not a button: it takes no tap, no
  /// hover and no focus, and a screen reader skips it.
  const ArDriveDropdownItem.divider({super.key})
      : content = const SizedBox.shrink(),
        onClick = null,
        isDivider = true;

  final Widget content;
  final Function()? onClick;
  final bool isDivider;

  /// A divider's height: its line and the space either side.
  static const double dividerHeight = 1 + 2 * ArDriveSpacing.xxs;

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

/// The line [ArDriveDropdownItem.divider] draws between two groups.
class _DropdownDivider extends StatelessWidget {
  const _DropdownDivider();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ArDriveSpacing.xxs),
        child: Container(
          height: 1,
          color: ArDriveTheme.of(context).themeData.colorTokens.strokeLow,
        ),
      ),
    );
  }
}
