import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Shortcut {
  final LogicalKeyboardKey modifier;
  final LogicalKeyboardKey key;
  final VoidCallback action;

  Shortcut({required this.modifier, required this.key, required this.action});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Shortcut && other.modifier == modifier && other.key == key;
  }

  @override
  int get hashCode => modifier.hashCode ^ key.hashCode;
}

class ShortcutHandler extends StatefulWidget {
  final Widget child;
  final List<Shortcut> shortcuts;

  const ShortcutHandler({
    Key? key,
    required this.child,
    required this.shortcuts,
  }) : super(key: key);

  @override
  ShortcutHandlerState createState() => ShortcutHandlerState();
}

class ShortcutHandlerState extends State<ShortcutHandler> {
  final FocusNode _focusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        for (var shortcut in widget.shortcuts) {
          if (HardwareKeyboard.instance
                  .isLogicalKeyPressed(shortcut.modifier) &&
              HardwareKeyboard.instance.isLogicalKeyPressed(shortcut.key)) {
            shortcut.action();
          }
        }
      },
      child: widget.child,
    );
  }
}
