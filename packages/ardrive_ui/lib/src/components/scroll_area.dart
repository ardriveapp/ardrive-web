import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Content that scrolls inside a dialog or sheet, and shows that it does.
///
/// When [child] is taller than the space it has, a scrollbar stays visible
/// beside it, and a divider with a soft shadow sits along its bottom edge
/// while more content waits below. Both go once the content fits, and the
/// divider goes at the bottom. Used by [ArDriveStandardModalNew] (with
/// `scrollableContent`) and [ArDriveBottomSheet], so a long dialog never
/// looks finished when it is not.
///
/// Its height is bounded by its parent: put it in a [Flexible] or a box
/// with a maximum height. It is as wide as its content.
class ArDriveScrollArea extends StatefulWidget {
  const ArDriveScrollArea({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;

  /// Padding inside the scroll view, around [child]. The scrollbar sits
  /// outside it, so a right padding keeps the bar off the content.
  final EdgeInsetsGeometry? padding;

  /// The key of the divider shown while more content waits below.
  static const moreBelowKey = ValueKey('ArDriveScrollArea.moreBelow');

  @override
  State<ArDriveScrollArea> createState() => _ArDriveScrollAreaState();
}

class _ArDriveScrollAreaState extends State<ArDriveScrollArea> {
  final _controller = ScrollController();
  bool _moreBelow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions) return;
    // Half a pixel: a fraction left by rounding is not more content.
    final moreBelow = position.extentAfter > 0.5;
    if (moreBelow != _moreBelow) setState(() => _moreBelow = moreBelow);
  }

  bool _onNotification(Notification notification) {
    if (notification is ScrollMetricsNotification ||
        notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _update();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Stack(
      // The parent's constraints as they are: filled when tight, sized to
      // the content when loose.
      fit: StackFit.passthrough,
      children: [
        NotificationListener<Notification>(
          onNotification: _onNotification,
          child: RawScrollbar(
            controller: _controller,
            // Always shown while the content scrolls: a bar that appears
            // only on scrolling never tells anyone there is more.
            thumbVisibility: true,
            thickness: 4,
            // Off the rounded edge of a dialog or sheet.
            crossAxisMargin: 6,
            radius: const Radius.circular(2),
            thumbColor: colors.iconLow,
            child: SingleChildScrollView(
              controller: _controller,
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
        // Laid over the bottom edge rather than below it, so it takes no
        // room and leaves the content's own width alone.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _moreBelow ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                key: _moreBelow ? ArDriveScrollArea.moreBelowKey : null,
                height: 1,
                decoration: BoxDecoration(
                  color: colors.strokeHigh,
                  boxShadow: [
                    BoxShadow(
                      color: colors.primitives.transparent900_32,
                      offset: const Offset(0, -2),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
