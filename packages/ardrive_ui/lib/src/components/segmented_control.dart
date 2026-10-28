import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// One choice in an [ArDriveSegmentedControl].
class ArDriveSegment<T> {
  const ArDriveSegment({
    required this.value,
    required this.label,
    this.icon,
    this.trailingIcon,
    this.wrap,
  });

  final T value;
  final String label;

  /// Drawn before the label, in the label's colour.
  final IconData? icon;

  /// Drawn after the label, such as the arrow of a segment that opens a menu.
  final IconData? trailingIcon;

  /// Wraps the segment, for instance in a menu that opens from it. A wrapped
  /// segment takes its taps from the wrapper: the control doesn't call
  /// [ArDriveSegmentedControl.onSelected] for it.
  final Widget Function(BuildContext context, Widget segment)? wrap;
}

/// Pick one of a few: a track of segments, the chosen one filled.
///
/// [expand] shares the full width equally between the segments, for a row of
/// amounts or payment methods; otherwise the control is as wide as its
/// labels, for a two-way switch such as Storage or USD.
class ArDriveSegmentedControl<T> extends StatelessWidget {
  const ArDriveSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.expand = false,
  });

  final List<ArDriveSegment<T>> segments;

  /// The chosen value, or null when none is, such as a custom amount typed
  /// beside a row of preset amounts.
  final T? selected;
  final ValueChanged<T> onSelected;
  final bool expand;

  static const double _padding = 4;

  /// The control is a regular button's height; each segment fills it less
  /// the track's padding.
  static double get height => ArDriveButtonSize.regular.height;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) children.add(const SizedBox(width: _padding));
      final segment = _Segment<T>(
        segment: segments[i],
        isSelected: segments[i].value == selected,
        onSelected: onSelected,
        expand: expand,
      );
      children.add(expand ? Expanded(child: segment) : segment);
    }

    return Container(
      height: height,
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: colorTokens.containerRaised,
        border: Border.all(color: colorTokens.strokeMid),
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _Segment<T> extends StatefulWidget {
  const _Segment({
    required this.segment,
    required this.isSelected,
    required this.onSelected,
    required this.expand,
  });

  final ArDriveSegment<T> segment;
  final bool isSelected;
  final ValueChanged<T> onSelected;
  final bool expand;

  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

class _SegmentState<T> extends State<_Segment<T>> {
  bool _hovering = false;
  bool _showFocus = false;

  void _select() => widget.onSelected(widget.segment.value);

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final segment = widget.segment;
    final isSelected = widget.isSelected;

    // The chosen segment is filled and its label inverted: about 8.5:1 in
    // light and 6.8:1 in dark.
    final foreground =
        isSelected ? colorTokens.containerRaised : colorTokens.textHigh;
    final background = isSelected
        ? colorTokens.textMid
        : _hovering
            ? colorTokens.buttonSecondaryHover
            : Colors.transparent;

    final label = Text(
      segment.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: typography.paragraphNormal(
        fontWeight: ArFontWeight.semiBold,
        color: foreground,
      ),
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (segment.icon != null) ...[
          Icon(segment.icon, size: 16, color: foreground),
          const SizedBox(width: 6),
        ],
        // Sharing a narrow width, a label shrinks to fit rather than being
        // cut off.
        Flexible(
          child: widget.expand
              ? FittedBox(fit: BoxFit.scaleDown, child: label)
              : label,
        ),
        if (segment.trailingIcon != null) ...[
          const SizedBox(width: 4),
          Icon(segment.trailingIcon, size: 16, color: foreground),
        ],
      ],
    );

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: widget.expand ? 4 : 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(ArDriveRadius.sm),
        border: _showFocus
            ? Border.all(color: colorTokens.textHigh, width: 2)
            : null,
      ),
      child: content,
    );

    final wrap = segment.wrap;
    if (wrap != null) {
      // The wrapper is the button; the control adds the chosen state and the
      // hover tint.
      return Semantics(
        selected: isSelected,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: wrap(context, body),
        ),
      );
    }

    // The focus detector sits outside the semantics so its focusable flag
    // merges into the segment's node rather than being excluded with the
    // label's.
    return FocusableActionDetector(
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
        selected: isSelected,
        label: segment.label,
        excludeSemantics: true,
        onTap: _select,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _select,
          child: body,
        ),
      ),
    );
  }
}
