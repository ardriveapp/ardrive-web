import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One value a menu or select field offers.
class ArDriveChoice<T> {
  const ArDriveChoice({
    required this.value,
    required this.label,
    this.icon,
    this.key,
  });

  final T value;
  final String label;

  /// Drawn between the tick and the label, such as a token's mark.
  final Widget? icon;

  /// Given to the choice's row, for tests to find it by.
  final Key? key;
}

/// A row in a menu that picks one value.
///
/// A 16 px slot before the label holds a tick when it is the current value,
/// and stays empty when it isn't, so the labels line up either way. Hover and
/// keyboard focus show the menu's hover colour.
class ArDriveChoiceItem extends StatefulWidget {
  const ArDriveChoiceItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final Widget? icon;
  final FocusNode? focusNode;

  /// Takes focus once shown, when the menu was opened from the keyboard.
  final bool autofocus;

  @override
  State<ArDriveChoiceItem> createState() => _ArDriveChoiceItemState();
}

class _ArDriveChoiceItemState extends State<ArDriveChoiceItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    // Not FocusableActionDetector's autofocus: that only takes focus when
    // nothing in the scope has it, and the button that opened the menu does.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.focusNode?.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;
    final colorTokens = theme.colorTokens;

    return Semantics(
      button: true,
      selected: widget.selected,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            color: _hovered || _focused ? theme.dropdownTheme.hoverColor : null,
            padding: const EdgeInsets.symmetric(horizontal: ArDriveSpacing.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: widget.selected
                      ? ArDriveIcons.checkmark(
                          size: 16,
                          color: colorTokens.textHigh,
                        )
                      : null,
                ),
                const SizedBox(width: ArDriveSpacing.xs),
                if (widget.icon != null) ...[
                  widget.icon!,
                  const SizedBox(width: ArDriveSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ArDriveTypographyNew.of(context).paragraphNormal(
                      color: colorTokens.textHigh,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens or closes a [ArDriveChoiceMenu]. [fromKeyboard] moves focus into
/// the menu, onto the current value.
typedef ArDriveChoiceToggle = void Function({bool fromKeyboard});

/// A menu that picks one of [choices], opened by the button [builder] draws.
///
/// The menu is the app's one menu card, on the navigator's overlay. Opened
/// from the keyboard it focuses the current value; Up and Down move, Enter
/// or Space picks, Escape or Tab closes, and focus goes back to the button.
/// Opened with the pointer it takes no focus, so nothing shows as
/// highlighted that the pointer isn't on.
class ArDriveChoiceMenu<T> extends StatefulWidget {
  const ArDriveChoiceMenu({
    super.key,
    required this.choices,
    required this.value,
    required this.onSelected,
    required this.builder,
    this.matchButtonWidth = false,
    this.minWidth = 0,
    this.alignmentOffset = Offset.zero,
    this.debugLabel = 'choice',
  });

  final List<ArDriveChoice<T>> choices;
  final T? value;
  final ValueChanged<T> onSelected;

  /// The button. It calls toggle when pressed, with fromKeyboard true when
  /// that was Enter, Space or Down rather than a click.
  final Widget Function(
    BuildContext context,
    bool isOpen,
    ArDriveChoiceToggle toggle,
  ) builder;

  /// Makes the menu at least as wide as the button, as a select field's is.
  final bool matchButtonWidth;
  final double minWidth;
  final Offset alignmentOffset;

  /// Each row's focus node is named this and its label, for tests.
  final String debugLabel;

  @override
  State<ArDriveChoiceMenu<T>> createState() => _ArDriveChoiceMenuState<T>();
}

class _ArDriveChoiceMenuState<T> extends State<ArDriveChoiceMenu<T>> {
  final _controller = ArDriveMenuController();
  final _buttonKey = GlobalKey();
  final _nodes = <FocusNode>[];

  bool _focusOnOpen = false;
  double _buttonWidth = 0;
  FocusNode? _returnFocusTo;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!_controller.isOpen) {
      // Focus was in the menu, which is going: back to the button.
      if (_nodes.any((node) => node.hasFocus)) {
        _returnFocusTo?.requestFocus();
      }
      _returnFocusTo = null;
    }
    if (mounted) setState(() {});
  }

  void _toggle({bool fromKeyboard = false}) {
    if (_controller.isOpen) {
      _controller.close();
      return;
    }
    _focusOnOpen = fromKeyboard;
    _returnFocusTo = FocusManager.instance.primaryFocus;
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    _buttonWidth = box != null && box.hasSize ? box.size.width : 0;
    _controller.open();
  }

  void _pick(T value) {
    _controller.close();
    widget.onSelected(value);
  }

  FocusNode _node(int index) {
    while (_nodes.length <= index) {
      _nodes.add(FocusNode());
    }
    return _nodes[index]
      ..debugLabel = '${widget.debugLabel} ${widget.choices[index].label}';
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab) {
      _controller.close();
      return KeyEventResult.handled;
    }
    final step = key == LogicalKeyboardKey.arrowDown
        ? 1
        : key == LogicalKeyboardKey.arrowUp
            ? -1
            : 0;
    if (step == 0) return KeyEventResult.ignored;
    final count = widget.choices.length;
    final current = _nodes.indexWhere((node) => node.hasFocus);
    final next = current < 0 ? 0 : (current + step).clamp(0, count - 1);
    _node(next).requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.choices;
    final selectedIndex = choices.indexWhere((c) => c.value == widget.value);
    final focusIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final minWidth = [
      widget.minWidth,
      if (widget.matchButtonWidth) _buttonWidth,
    ].reduce((a, b) => a > b ? a : b);

    return ArDriveMenuAnchor(
      controller: _controller,
      alignmentOffset: widget.alignmentOffset,
      menuChildren: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < choices.length; i++)
                    ArDriveChoiceItem(
                      key: choices[i].key,
                      label: choices[i].label,
                      icon: choices[i].icon,
                      selected: i == selectedIndex,
                      focusNode: _node(i),
                      autofocus: _focusOnOpen && i == focusIndex,
                      onPressed: () => _pick(choices[i].value),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
      child: KeyedSubtree(
        key: _buttonKey,
        child: widget.builder(context, _controller.isOpen, _toggle),
      ),
    );
  }
}

/// A button that opens a [ArDriveChoiceMenu]: a click, or Enter, Space or
/// Down from the keyboard. [builder] draws its face, told whether the
/// pointer is over it and whether it has keyboard focus.
class ArDriveChoiceButton extends StatefulWidget {
  const ArDriveChoiceButton({
    super.key,
    required this.toggle,
    required this.builder,
    this.enabled = true,
    this.semanticLabel,
    this.semanticValue,
    this.focusNode,
  });

  final ArDriveChoiceToggle toggle;
  final Widget Function(BuildContext context, bool hovered, bool focused)
      builder;
  final bool enabled;
  final String? semanticLabel;
  final String? semanticValue;
  final FocusNode? focusNode;

  @override
  State<ArDriveChoiceButton> createState() => _ArDriveChoiceButtonState();
}

class _ArDriveChoiceButtonState extends State<ArDriveChoiceButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // A button that names itself keeps its face out of the semantics, or a
    // screen reader would read the value twice: in the label and as the
    // value.
    final namesItself =
        widget.semanticLabel != null || widget.semanticValue != null;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      excludeSemantics: namesItself,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        focusNode: widget.focusNode,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowDown): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.toggle(fromKeyboard: true);
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? () => widget.toggle() : null,
          child: widget.builder(context, _hovered, _focused),
        ),
      ),
    );
  }
}

/// A form field that picks one of [choices]: drawn as [ArDriveTextFieldNew]
/// is, with its fill, edge, radius and height, and a label above. It opens
/// an [ArDriveChoiceMenu] under it, at least as wide as the field. With no
/// [onChanged] it is disabled.
class ArDriveSelectField<T> extends StatelessWidget {
  const ArDriveSelectField({
    super.key,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.label,
    this.hintText,
    this.errorText,
    this.isFieldRequired = false,
    this.debugLabel = 'select',
  });

  final List<ArDriveChoice<T>> choices;
  final T? value;
  final ValueChanged<T>? onChanged;
  final String? label;
  final String? hintText;
  final String? errorText;
  final bool isFieldRequired;
  final String debugLabel;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final enabled = onChanged != null;
    final selected = choices.where((c) => c.value == value).firstOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                text: label,
                children: [if (isFieldRequired) const TextSpan(text: ' *')],
              ),
              style: typography.paragraphNormal(
                color: colorTokens.textLow,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
        ArDriveChoiceMenu<T>(
          choices: choices,
          value: value,
          onSelected: (value) => onChanged?.call(value),
          matchButtonWidth: true,
          alignmentOffset: const Offset(0, 4),
          debugLabel: debugLabel,
          builder: (context, isOpen, toggle) => ArDriveChoiceButton(
            toggle: toggle,
            enabled: enabled,
            semanticLabel: label ?? hintText,
            semanticValue: selected?.label,
            builder: (context, hovered, focused) => Container(
              padding: const EdgeInsets.fromLTRB(20, 13, 12, 13),
              decoration: BoxDecoration(
                color: enabled
                    ? colorTokens.inputDefault
                    : colorTokens.inputDisabled,
                borderRadius: BorderRadius.circular(ArDriveRadius.control),
                border: Border.all(
                  color: errorText != null
                      ? colorTokens.strokeRed
                      : enabled && (isOpen || focused)
                          ? colorTokens.strokeHigh
                          : colorTokens.strokeMid,
                ),
              ),
              child: Row(
                children: [
                  if (selected?.icon != null) ...[
                    selected!.icon!,
                    const SizedBox(width: ArDriveSpacing.xs),
                  ],
                  Expanded(
                    child: Text(
                      selected?.label ?? hintText ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: typography.paragraphNormal(
                        color: selected != null && enabled
                            ? colorTokens.textMid
                            : colorTokens.textXLow,
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
                  ),
                  const SizedBox(width: ArDriveSpacing.xs),
                  ArDriveIcons.carretDown(
                    size: 20,
                    color: enabled ? colorTokens.iconMid : colorTokens.iconLow,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorText!,
              style: typography.paragraphNormal(
                color: colorTokens.strokeRed,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
      ],
    );
  }
}
