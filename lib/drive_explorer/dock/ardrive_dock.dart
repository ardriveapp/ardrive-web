import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class ArDriveDock extends StatefulWidget {
  const ArDriveDock({required this.child, super.key});

  final Widget child;

  @override
  State<ArDriveDock> createState() => ArDriveDockState();

  static ArDriveDockState of(BuildContext context) {
    return context.findAncestorStateOfType<ArDriveDockState>()!;
  }
}

class ArDriveDockState extends State<ArDriveDock> {
  OverlayEntry? _overlayEntry;
  bool isCollapsed = true;

  @override
  void initState() {
    super.initState();
  }

  void showOverlay(BuildContext context, Widget content, {double? height}) {
    _overlayEntry = _createOverlayEntry(content, height: height);
    Overlay.of(context).insert(_overlayEntry!);
  }

  OverlayEntry _createOverlayEntry(Widget content, {double? height}) {
    return OverlayEntry(
      builder: (context) => Positioned(
        bottom: 0,
        right: 20,
        child: _DockContent(
          content: content,
          height: height,
        ),
      ),
    );
  }

  void removeOverlay() {
    _overlayEntry?.remove();
  }

  @override
  dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => widget.child,
        )
      ],
    );
  }
}

class _DockContent extends StatefulWidget {
  const _DockContent({
    required this.content,
    this.height,
  });

  final Widget content;
  final double? height;

  @override
  State<_DockContent> createState() => __DockContentState();
}

class __DockContentState extends State<_DockContent> {
  bool isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    if (isCollapsed) {
      return ArDriveCard(
        height: 64,
        width: 400,
        elevation: 2,
        withRedLineOnTop: true,
        contentPadding: EdgeInsets.zero,
        boxShadow: BoxShadowCard.shadow80,
        content: Material(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      ArDriveIconButton(
                        icon: ArDriveIcons.carretUp(),
                        onPressed: () {
                          setState(() {
                            isCollapsed = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(child: widget.content),
            ],
          ),
        ),
      );
    }

    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveCard(
      height: widget.height ?? 202,
      width: 400,
      elevation: 2,
      contentPadding: EdgeInsets.zero,
      boxShadow: BoxShadowCard.shadow80,
      content: Material(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SizedBox(
              height: 6,
              child: Container(
                color: colorTokens.containerRed,
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ArDriveIconButton(
                          icon: ArDriveIcons.carretDown(),
                          onPressed: () {
                            setState(() {
                              isCollapsed = true;
                            });
                          },
                          tooltip: 'Collapse',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: widget.content,
            ),
          ],
        ),
      ),
    );
  }
}
