import 'dart:async';

import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_portal/flutter_portal.dart';

class ArDriveDropdown extends StatefulWidget {
  const ArDriveDropdown({
    super.key,
    required this.items,
    required this.child,
    this.contentPadding,
    this.height = 60,
    this.width = 200,
    this.anchor = const Aligned(
      follower: Alignment.topLeft,
      target: Alignment.bottomLeft,
      offset: Offset(0, 4),
    ),
  });

  final double height;
  final double width;
  final List<ArDriveDropdownItem> items;
  final Widget child;
  final EdgeInsets? contentPadding;
  final Anchor anchor;

  @override
  State<ArDriveDropdown> createState() => _ArDriveDropdownState();
}

class _ArDriveDropdownState extends State<ArDriveDropdown> {
  bool? visible;

  @override
  Widget build(BuildContext context) {
    double dropdownHeight = widget.items.length * widget.height;

    return ArDriveOverlay(
      visible: visible,
      anchor: widget.anchor,
      content: TweenAnimationBuilder<double>(
        duration: kThemeAnimationDuration,
        curve: Curves.easeOut,
        tween: Tween(begin: 50, end: dropdownHeight),
        builder: (context, size, _) {
          return SizedBox(
            height: size,
            child: ArDriveCard(
              contentPadding: EdgeInsets.zero,
              content: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  children: List.generate(widget.items.length, (index) {
                    return FutureBuilder<bool>(
                        future: Future.delayed(
                          Duration(milliseconds: (index + 1) * 50),
                          () => true,
                        ),
                        builder: (context, snapshot) {
                          return AnimatedCrossFade(
                            duration: const Duration(milliseconds: 100),
                            firstChild: SizedBox(
                              width: widget.width,
                              height: widget.height,
                              child: GestureDetector(
                                onTap: () {
                                  widget.items[index].onClick?.call();
                                  setState(() {
                                    visible = false;
                                  });
                                },
                                child: widget.items[index],
                              ),
                            ),
                            secondChild: SizedBox(
                              height: 0,
                              width: widget.width,
                            ),
                            crossFadeState: snapshot.hasData && snapshot.data!
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                          );
                        });
                  }),
                ),
              ),
              boxShadow: BoxShadowCard.shadow80,
            ),
          );
        },
      ),
      child: widget.child,
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
  });

  final Widget child;
  final Widget content;
  final EdgeInsets contentPadding;
  final Anchor anchor;
  final bool? visible;
  @override
  State<ArDriveOverlay> createState() => _ArDriveOverlayState();
}

class _ArDriveOverlayState extends State<ArDriveOverlay> {
  @override
  void initState() {
    super.initState();
    _updateVisibleState();
  }

  @override
  void didUpdateWidget(oldWidget) {
    super.didUpdateWidget(oldWidget);
    setState(() {
      _updateVisibleState();
    });
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
    return Barrier(
      onClose: () {
        setState(() {
          _visible = !_visible;
        });
      },
      visible: _visible,
      child: PortalTarget(
        anchor: widget.anchor,
        portalFollower: widget.content,
        visible: _visible,
        child: GestureDetector(
          onTap: () {
            print('on tap');
            setState(() {
              _visible = true;
            });
          },
          child: IgnorePointer(
            ignoring: _visible,
            child: widget.child,
          ),
        ),
      ),
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
    final theme = ArDriveTheme.of(context).themeData.dropdownTheme;

    return MouseRegion(
      onHover: (event) {
        setState(() {
          hovering = true;
        });
      },
      onExit: (event) => setState(() {
        hovering = false;
      }),
      child: Container(
        color: hovering ? theme.hoverColor : theme.backgroundColor,
        alignment: Alignment.center,
        child: widget.content,
      ),
    );
  }
}
