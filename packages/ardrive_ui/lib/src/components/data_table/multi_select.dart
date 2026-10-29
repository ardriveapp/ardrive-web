import 'package:ardrive_utils/ardrive_utils.dart';
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
/// - Holding the multi-select key (Ctrl on Windows, Cmd elsewhere) shows them
///   all too, as a shortcut.
///
/// The column the boxes sit in is always reserved and a box fades in place,
/// so a row's content never moves when its box appears. Ticking is the box's
/// alone: what a click on the row itself does is the list's business.
///
/// The explorer's table ([ArDriveDataTable]) and the drives list both go by
/// this, so the two lists agree.
abstract final class ArDriveMultiSelect {
  /// Whether the multi-select key is held: Ctrl on Windows, Cmd elsewhere.
  static bool get keyPressed => AppPlatform.isWindows()
      ? HardwareKeyboard.instance.isControlPressed
      : HardwareKeyboard.instance.isMetaPressed;

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
/// Hidden, it is transparent and takes no pointer, so a click there lands on
/// the row; it stays in the focus order, and focus on it shows it.
class ArDriveMultiSelectBox extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.centerLeft,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: ArDriveMultiSelect.fade,
            child: child,
          ),
        ),
      ),
    );
  }
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
  bool _keyHeld = false;

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
