import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// When a list shows its checkboxes.
///
/// Only while the reader is choosing several rows: once a row is ticked,
/// while the multi-select key is held, or after a long press on a touch
/// screen. The rest of the time the checkboxes are hidden and a click on a row
/// only chooses it. The explorer's table ([ArDriveDataTable]) and the drives
/// list both go by this, so the two lists agree on when ticking is on offer.
abstract final class ArDriveMultiSelect {
  /// Whether the multi-select key is held: Ctrl on Windows, Cmd elsewhere.
  static bool get keyPressed => AppPlatform.isWindows()
      ? HardwareKeyboard.instance.isControlPressed
      : HardwareKeyboard.instance.isMetaPressed;

  /// Whether a list shows its checkboxes.
  static bool showsCheckboxes({
    required bool anyTicked,
    required bool keyHeld,
    bool longPressed = false,
  }) =>
      longPressed || anyTicked || keyHeld;
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
