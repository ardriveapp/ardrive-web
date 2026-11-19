import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One choice in an [ArDriveIconSegmentedControl].
class ArDriveIconSegment<T> {
  const ArDriveIconSegment({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final IconData icon;

  /// The tooltip, and the name a screen reader reads.
  final String label;
}

/// Pick one of a few by icon, as a folder's List and Gallery view switch does:
/// joined buttons in one track, the chosen one filled. Each has a tooltip and
/// is a button to a screen reader, named by its label.
///
/// It takes Tab, and Enter or Space on the focused one. The left and right
/// arrows move to the neighbour and choose it, as a radio group does.
class ArDriveIconSegmentedControl<T> extends StatelessWidget {
  const ArDriveIconSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
  });

  final List<ArDriveIconSegment<T>> segments;
  final T? selected;
  final ValueChanged<T> onSelected;

  static const double _padding = 4;

  /// The control is a regular button's height, like [ArDriveSegmentedControl].
  static double get height => ArDriveButtonSize.regular.height;

  @override
  Widget build(BuildContext context) {
    final tokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Container(
      height: height,
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: tokens.containerRaised,
        border: Border.all(color: tokens.strokeMid),
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: _padding),
            _IconSegment<T>(
              segment: segments[i],
              isSelected: segments[i].value == selected,
              onSelected: onSelected,
              previous: i > 0 ? segments[i - 1].value : null,
              next: i < segments.length - 1 ? segments[i + 1].value : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _IconSegment<T> extends StatefulWidget {
  const _IconSegment({
    required this.segment,
    required this.isSelected,
    required this.onSelected,
    required this.previous,
    required this.next,
  });

  final ArDriveIconSegment<T> segment;
  final bool isSelected;
  final ValueChanged<T> onSelected;
  final T? previous;
  final T? next;

  @override
  State<_IconSegment<T>> createState() => _IconSegmentState<T>();
}

class _IconSegmentState<T> extends State<_IconSegment<T>> {
  bool _hovering = false;
  bool _showFocus = false;

  void _select() => widget.onSelected(widget.segment.value);

  @override
  Widget build(BuildContext context) {
    final tokens = ArDriveTheme.of(context).themeData.colorTokens;
    final segment = widget.segment;
    // The chosen segment is filled and its glyph inverted, as in
    // [ArDriveSegmentedControl].
    final foreground =
        widget.isSelected ? tokens.containerRaised : tokens.textHigh;
    final background = widget.isSelected
        ? tokens.textMid
        : _hovering
            ? tokens.buttonSecondaryHover
            : Colors.transparent;

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(ArDriveRadius.sm),
        border:
            _showFocus ? Border.all(color: tokens.textHigh, width: 2) : null,
      ),
      child: Icon(segment.icon, size: 20, color: foreground),
    );

    // The key handler is outside the detector: key events go up from the
    // focused node, which is the detector's own.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final target = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowLeft => widget.previous,
          LogicalKeyboardKey.arrowRight => widget.next,
          _ => null,
        };
        if (target == null) return KeyEventResult.ignored;
        widget.onSelected(target);
        return KeyEventResult.handled;
      },
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (show) => setState(() => _hovering = show),
        onShowFocusHighlight: (show) => setState(() => _showFocus = show),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _select();
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          selected: widget.isSelected,
          label: segment.label,
          excludeSemantics: true,
          onTap: _select,
          child: ArDriveTooltip(
            message: segment.label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _select,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
