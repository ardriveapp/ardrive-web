import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A checkbox: for the pointer, the keyboard and a screen reader.
///
/// It follows [checked], [isDisabled] and [isIndeterminate] as the caller
/// changes them, so a caller never needs to key it by its state - a key that
/// changes with the state rebuilds the box on every tick and throws away its
/// keyboard focus.
class ArDriveCheckBox extends StatefulWidget {
  const ArDriveCheckBox({
    super.key,
    this.checked = false,
    this.isDisabled = false,
    this.isIndeterminate = false,
    this.title,
    this.titleStyle,
    this.onChange,
    this.titleWidget,
    this.useNewIcons = true,
    this.iconSize = 18.5,
    this.semanticLabel,
    this.inTabOrder = true,
  });

  /// Whether Tab stops here. False for a box that a focused row ticks with
  /// Space, as in a file manager: the row is the stop, so a 100-row page is
  /// not 100 more. The box stays tappable and stays a checkbox to a screen
  /// reader.
  final bool inTabOrder;

  /// What a screen reader calls the box when it has no [title]: the row it
  /// ticks, say.
  final String? semanticLabel;

  /// Whether it is ticked. Followed as it changes.
  final bool checked;
  final bool isDisabled;

  /// If true, the checkbox will be rendered as indeterminate.
  final bool isIndeterminate;
  final String? title;

  /// A widget that will be used as the title of the checkbox.
  /// It only shows if [title] is null.
  final Widget? titleWidget;
  final TextStyle? titleStyle;
  final Function(bool value)? onChange;

  final bool useNewIcons;

  final double iconSize;

  @override
  State<ArDriveCheckBox> createState() => ArDriveCheckBoxState();
}

enum CheckBoxState { normal, hover, indeterminate, checked, disabled }

@visibleForTesting
class ArDriveCheckBoxState extends State<ArDriveCheckBox> {
  @visibleForTesting
  late CheckBoxState state;

  @visibleForTesting
  late bool checked;

  /// Whether the keyboard has focus here, so the box shows a ring.
  bool _showFocus = false;

  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'ArDriveCheckBox',
    skipTraversal: !widget.inTabOrder,
  );

  @override
  void initState() {
    _follow();
    super.initState();
  }

  @override
  void didUpdateWidget(ArDriveCheckBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The caller's value wins on every rebuild. A tick the caller refused - a
    // locked table, say - goes back rather than staying drawn.
    _follow();
    _focusNode.skipTraversal = !widget.inTabOrder;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _follow() {
    checked = widget.checked;
    if (checked && !widget.isDisabled) {
      state = CheckBoxState.checked;
    } else if (widget.isDisabled) {
      state = CheckBoxState.disabled;
    } else if (widget.isIndeterminate) {
      state = CheckBoxState.indeterminate;
    } else {
      state = CheckBoxState.normal;
    }
  }

  void _toggle() {
    switch (state) {
      case CheckBoxState.normal:
      case CheckBoxState.hover:
        setState(() {
          state = CheckBoxState.checked;
          checked = true;
        });
        break;
      case CheckBoxState.indeterminate:
        setState(() {
          checked = !checked;
        });
        break;
      case CheckBoxState.checked:
        setState(() {
          state = CheckBoxState.normal;
          checked = false;
        });
        break;
      case CheckBoxState.disabled:
        break;
    }
    widget.onChange?.call(checked);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.isDisabled;

    // A checkbox to the keyboard and to a screen reader as well as to the
    // pointer: it takes focus, Space ticks it (on the web, as in a browser,
    // Enter does not), and it is announced
    // as a checkbox with its state. It was a bare GestureDetector, reachable
    // by the mouse alone.
    // The focus node's semantics join the checkbox's own node, so a screen
    // reader finds one focusable, tickable checkbox.
    return Semantics(
      container: true,
      checked: checked && state != CheckBoxState.indeterminate,
      mixed: state == CheckBoxState.indeterminate ? true : null,
      enabled: enabled,
      label: widget.title ?? widget.semanticLabel,
      onTap: enabled ? _toggle : null,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: _focusNode,
        onShowFocusHighlight: (show) => setState(() => _showFocus = show),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          // The Semantics above carries the tap, once.
          excludeFromSemantics: true,
          onTap: _toggle,
          child: _content(),
        ),
      ),
    );
  }

  Widget _content() {
    return widget.useNewIcons
        ? _buildNewIcons()
        : ArDriveClickArea(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _focusRing(state == CheckBoxState.indeterminate
                    ? ArDriveIcon(
                        icon: ArDriveIconsData.minus_rectangle,
                        size: 22,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colorTokens
                            .iconHigh,
                      )
                    : AnimatedContainer(
                        height: widget.iconSize,
                        width: widget.iconSize,
                        margin: const EdgeInsets.fromLTRB(3.25, 3.5, 5, 4),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(checkboxBorderRadius),
                          border: Border.all(
                            color: _boxColor(),
                            width: 2,
                          ),
                          color: _backgroundColor(),
                        ),
                        duration: const Duration(milliseconds: 300),
                        child: checked
                            ? ArDriveIcon(
                                icon: ArDriveIconsData.checkmark,
                                size: 12,
                                color: _checkColor(),
                              )
                            : null,
                      )),
                if (_buildTitle() != null) ...[
                  const SizedBox(width: 8.0),
                  _buildTitle()!,
                ]
              ],
            ),
          );
  }

  Widget _buildNewIcons() {
    return ArDriveClickArea(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _focusRing(
            state == CheckBoxState.indeterminate
                ? ArDriveIcon(
                    icon: ArDriveIconsData.minus_rectangle,
                    size: widget.iconSize,
                    color:
                        ArDriveTheme.of(context).themeData.colorTokens.iconHigh,
                  )
                : checked
                    ? ArDriveIcons.checked(size: widget.iconSize)
                    : ArDriveIcons.box(size: widget.iconSize),
          ),
          if (_buildTitle() != null) ...[
            const SizedBox(width: 8.0),
            _buildTitle()!,
          ]
        ],
      ),
    );
  }

  /// The keyboard's ring around the box, in the focus colour the toggle and
  /// the shared file page use. Outside the box, so it never moves it.
  Widget _focusRing(Widget box) {
    return DecoratedBox(
      key: const Key('checkboxFocusRing'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _showFocus
              ? ArDriveTheme.of(context).themeData.colorTokens.textHigh
              : Colors.transparent,
          width: 2,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      ),
      child: box,
    );
  }

  Widget? _buildTitle() {
    if (widget.title != null) {
      return Flexible(
        // Said once, as the checkbox's label: read again as text, a titled
        // box was announced twice.
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              widget.title!,
              style: widget.titleStyle ??
                  ArDriveTypographyNew.of(context).paragraphNormal(
                    color: _textColor(),
                  ),
            ),
          ),
        ),
      );
    }

    if (widget.title == null && widget.titleWidget != null) {
      // A widget title is the label only when nothing else names the box.
      return widget.semanticLabel == null
          ? widget.titleWidget!
          : ExcludeSemantics(child: widget.titleWidget!);
    }

    return null;
  }

  Color _boxColor() {
    switch (state) {
      case CheckBoxState.indeterminate:
      case CheckBoxState.checked:
      case CheckBoxState.hover:
        return ArDriveTheme.of(context).themeData.colorTokens.iconHigh;
      case CheckBoxState.disabled:
        return ArDriveTheme.of(context).themeData.colorTokens.textXLow;
      case CheckBoxState.normal:
        return ArDriveTheme.of(context).themeData.colorTokens.iconHigh;
    }
  }

  Color _backgroundColor() {
    switch (state) {
      case CheckBoxState.indeterminate:
      case CheckBoxState.checked:
      case CheckBoxState.hover:
        return ArDriveTheme.of(context).themeData.colorTokens.iconHigh;
      case CheckBoxState.disabled:
        return Colors.transparent;

      case CheckBoxState.normal:
        return Colors.transparent;
    }
  }

  Color _checkColor() {
    switch (state) {
      case CheckBoxState.indeterminate:
      case CheckBoxState.checked:
      case CheckBoxState.hover:
        return ArDriveTheme.of(context).themeData.colorTokens.containerL0;
      case CheckBoxState.disabled:
        return ArDriveTheme.of(context).themeData.colorTokens.textXLow;
      case CheckBoxState.normal:
        return ArDriveTheme.of(context).themeData.colorTokens.iconHigh;
    }
  }

  Color _textColor() {
    switch (state) {
      case CheckBoxState.indeterminate:
      case CheckBoxState.checked:
      case CheckBoxState.hover:
      case CheckBoxState.normal:
        return ArDriveTheme.of(context).themeData.colorTokens.textHigh;
      case CheckBoxState.disabled:
        return ArDriveTheme.of(context).themeData.colorTokens.textXLow;
    }
  }
}
