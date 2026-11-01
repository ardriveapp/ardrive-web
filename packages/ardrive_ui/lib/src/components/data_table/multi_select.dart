import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// When a list shows its checkboxes: the file-manager pattern, as Google
/// Drive, Dropbox and OneDrive have it.
///
/// - A row's box shows while the pointer is on that row, or while the row has
///   keyboard focus.
/// - Once any box is ticked, every row's box shows, and select-all in the
///   header, until the selection is cleared.
/// - On a touch screen, a long press starts selecting.
/// - Holding the multi-select key (Cmd on macOS and iOS, Ctrl everywhere
///   else) shows them all too, as a shortcut.
/// - The row is the Tab stop, and Space on it ticks its box; select-all is a
///   stop only while selecting.
///
/// The column the boxes sit in is always reserved and a box fades in place,
/// so a row's content never moves when its box appears. Ticking is the box's
/// alone: what a click on the row itself does is the list's business.
///
/// The explorer's table ([ArDriveDataTable]) and the drives list both go by
/// this, so the two lists agree.
abstract final class ArDriveMultiSelect {
  /// Whether the multi-select key is held: Cmd on macOS and iOS, Ctrl
  /// everywhere else - Windows, Linux, ChromeOS, Android - in the app and on
  /// the web alike.
  static bool get keyPressed => usesCmd
      ? HardwareKeyboard.instance.isMetaPressed
      : HardwareKeyboard.instance.isControlPressed;

  /// Whether that key is Cmd rather than Ctrl. [defaultTargetPlatform] is
  /// the reader's OS on the web too.
  static bool get usesCmd =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether the reader is choosing several rows, which shows every row's box
  /// and the header's select-all.
  static bool isSelecting({
    required bool anyTicked,
    required bool keyHeld,
    bool longPressed = false,
  }) =>
      longPressed || anyTicked || keyHeld;

  /// Whether one row's box shows: while selecting, or while the pointer is on
  /// the row or the row has keyboard focus.
  static bool showsRowCheckbox({
    required bool selecting,
    bool hovered = false,
    bool focused = false,
  }) =>
      selecting || hovered || focused;

  /// How long a box takes to fade in or out.
  static const fade = Duration(milliseconds: 150);
}

/// A row's checkbox, or the header's select-all, in a column of [width]
/// that is reserved whether or not the box shows.
///
/// Hidden, it is transparent and a pointer passes through it to the row, so
/// a click there chooses the row. It stays in the focus order and in the
/// semantics tree: Tab reaches it, focus on it shows it, and a screen reader
/// can tick it whether or not it shows.
class ArDriveMultiSelectBox extends StatefulWidget {
  const ArDriveMultiSelectBox({
    super.key,
    required this.visible,
    required this.width,
    required this.child,
  });

  final bool visible;
  final double width;
  final Widget child;

  @override
  State<ArDriveMultiSelectBox> createState() => _ArDriveMultiSelectBoxState();
}

class _ArDriveMultiSelectBoxState extends State<ArDriveMultiSelectBox> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final visible = widget.visible || _focused;

    return _FullHeightTap(
        enabled: visible,
        child: SizedBox(
          width: widget.width,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: _PointerPassThrough(
                passThrough: !visible,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: ArDriveMultiSelect.fade,
                  // Transparent is not gone: a screen reader still finds it.
                  alwaysIncludeSemantics: true,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ));
  }
}

/// Makes a shown box's whole column, at the height of the row it sits in, its
/// tap target: a finger a few pixels off the 18 px glyph ticks the box rather
/// than opening the row.
///
/// The box does not grow, so the row's layout does not change; a tap in the
/// column outside the glyph is handed to the glyph.
class _FullHeightTap extends SingleChildRenderObjectWidget {
  const _FullHeightTap({required this.enabled, super.child});

  final bool enabled;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFullHeightTap(enabled);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFullHeightTap renderObject,
  ) =>
      renderObject.enabled = enabled;
}

class _RenderFullHeightTap extends RenderProxyBox {
  _RenderFullHeightTap(this.enabled);

  bool enabled;

  /// Inside the glyph, which is at the column's left and centred.
  static const _glyphX = 8.0;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final data = parentData;
    final rowParent = parent;
    if (!enabled ||
        child == null ||
        data is! BoxParentData ||
        rowParent is! RenderBox ||
        !rowParent.hasSize) {
      return super.hitTest(result, position: position);
    }
    final rowHeight = rowParent.size.height;
    final top = data.offset.dy;
    final inColumn = position.dx >= 0 &&
        position.dx < size.width &&
        position.dy + top >= 0 &&
        position.dy + top < rowHeight;
    if (!inColumn) return false;
    if (size.contains(position) && super.hitTest(result, position: position)) {
      return true;
    }
    final onGlyph = Offset(_glyphX, size.height / 2);
    if (hitTestChildren(result, position: onGlyph)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

/// Lets a pointer through to what is behind while [passThrough], without
/// touching semantics: [IgnorePointer] also blocks a screen reader's actions.
class _PointerPassThrough extends SingleChildRenderObjectWidget {
  const _PointerPassThrough({required this.passThrough, super.child});

  final bool passThrough;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPointerPassThrough(passThrough);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPointerPassThrough renderObject,
  ) =>
      renderObject.passThrough = passThrough;
}

class _RenderPointerPassThrough extends RenderProxyBox {
  _RenderPointerPassThrough(this.passThrough);

  bool passThrough;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !passThrough && super.hitTest(result, position: position);
}

/// Builds [builder] with whether the multi-select key is held, and builds it
/// again when the key is pressed or released.
///
/// The key is heard wherever focus is, as the explorer's table hears it: it is
/// held before the click it changes, and nothing has focus in the list yet.
class ArDriveMultiSelectKey extends StatefulWidget {
  const ArDriveMultiSelectKey({super.key, required this.builder});

  final Widget Function(BuildContext context, bool keyHeld) builder;

  @override
  State<ArDriveMultiSelectKey> createState() => _ArDriveMultiSelectKeyState();
}

class _ArDriveMultiSelectKeyState extends State<ArDriveMultiSelectKey> {
  /// A key already held when this is built counts.
  bool _keyHeld = ArDriveMultiSelect.keyPressed;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final held = ArDriveMultiSelect.keyPressed;
    if (mounted && held != _keyHeld) {
      setState(() => _keyHeld = held);
    }
    // Heard, never taken: the key means other things too.
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _keyHeld);
}
