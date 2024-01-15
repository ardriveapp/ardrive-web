import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_portal/flutter_portal.dart';

export 'package:flutter_portal/flutter_portal.dart'
    show Anchor, Aligned, Filled;

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

  // retruns the alignment based if the current widget y coordinate is greater than half the screen height
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

  @override
  void didChangeDependencies() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final renderBox = context.findRenderObject() as RenderBox?;

        final position = renderBox?.localToGlobal(Offset.zero);

        if (position != null && widget.calculateVerticalAlignment != null) {
          final y = position.dy;

          final screenHeight = MediaQuery.of(context).size.height;

          Alignment alignment;

          alignment =
              widget.calculateVerticalAlignment!.call(y > screenHeight / 2);

          _anchor = Aligned(
            follower: alignment,
            target: Alignment.bottomLeft,
          );
        }
      });
    }

    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    dropdownHeight = widget.maxHeight ?? widget.items.length * widget.height;

    final dropdownTheme = ArDriveTheme.of(context).themeData.dropdownTheme;

    return ArDriveOverlay(
      onVisibleChange: (value) {
        setState(() {
          visible = value;
        });
      },
      visible: visible,
      anchor: _anchor,
      content: _ArDriveDropdownContent(
        height: dropdownHeight,
        child: ArDriveCard(
          border: Border.all(
            color: ArDriveTheme.of(context)
                .themeData
                .dropdownTheme
                .backgroundColor,
            width: 1,
          ),
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
                    Column(
                      children: List.generate(widget.items.length, (index) {
                        return GestureDetector(
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
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    widget.items[index],
                                    if (index != widget.items.length - 1)
                                      Divider(
                                        height: 0,
                                        thickness: widget.dividerThickness ?? 1,
                                        color: ArDriveTheme.of(context)
                                            .themeData
                                            .colors
                                            .themeBorderDefault,
                                      ),
                                  ],
                                ),
                              ],
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

class Barrier extends StatelessWidget {
  const Barrier({
    Key? key,
    required this.onClose,
    required this.visible,
    required this.child,
  }) : super(key: key);

  final Widget child;
  final VoidCallback onClose;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return PortalTarget(
      visible: visible,
      closeDuration: kThemeAnimationDuration,
      portalFollower: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
      ),
      child: child,
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
