import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/dev_tools/shortcut_handler.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
// ignore: depend_on_referenced_packages
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class KeyboardHandler extends StatefulWidget {
  final Widget child;
  const KeyboardHandler({super.key, required this.child});

  @override
  State<KeyboardHandler> createState() => _KeyboardHandlerState();
}

class _KeyboardHandlerState extends State<KeyboardHandler> {
  final _focusTable = FocusNode();
  bool ctrlMetaPressed = false;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => KeyboardListenerBloc(),
      child: BlocBuilder<KeyboardListenerBloc, KeyboardListenerState>(
        builder: (context, state) {
          final keyboardListenerBloc = context.read<KeyboardListenerBloc>();
          return KeyboardListener(
            focusNode: _focusTable,
            autofocus: true,
            onKeyEvent: (event) async {
              // detect if ctrl + v or cmd + v is pressed
              if (await isCtrlOrMetaKeyPressed(event)) {
                if (event is KeyDownEvent) {
                  setState(() => ctrlMetaPressed = true);
                }
              } else {
                setState(() => ctrlMetaPressed = false);
              }

              if (!mounted) return;
              keyboardListenerBloc.add(
                KeyboardListenerUpdateCtrlMetaPressed(
                  isPressed: ctrlMetaPressed,
                ),
              );
            },
            child: widget.child,
          );
        },
      ),
    );
  }
}

Future<bool> isCtrlOrMetaKeyPressed(KeyEvent event) async {
  try {
    final userAgent = (await DeviceInfoPlugin().webBrowserInfo).userAgent;
    late bool ctrlMetaKeyPressed;
    if (userAgent != null && isApple(userAgent)) {
      ctrlMetaKeyPressed = HardwareKeyboard.instance.isMetaPressed;
    } else {
      ctrlMetaKeyPressed = HardwareKeyboard.instance.isControlPressed;
    }
    return ctrlMetaKeyPressed;
  } catch (e) {
    if (!AppPlatform.isMobile) {
      logger.e('Unable to compute platform');
    }

    return false;
  }
}

bool isApple(String userAgent) {
  const platforms = [
    'Mac',
    'iPad Simulator',
    'iPhone Simulator',
    'iPod Simulator',
    'iPad',
    'iPhone',
    'iPod',
  ];
  for (var platform in platforms) {
    if (userAgent.contains(platform)) {
      return true;
    }
  }
  return false;
}

class ArDriveDevToolsShortcuts extends StatelessWidget {
  final Widget child;
  final List<Shortcut>? customShortcuts;

  const ArDriveDevToolsShortcuts({
    super.key,
    required this.child,
    this.customShortcuts,
  });

  @override
  Widget build(BuildContext context) {
    // Define the shortcuts and their actions
    final List<Shortcut> shortcuts = [
      Shortcut(
        modifier: LogicalKeyboardKey.controlLeft,
        key: LogicalKeyboardKey.keyQ,
        action: () {
          if (HardwareKeyboard.instance.isShiftPressed) {
            ArDriveDevTools.instance.showDevTools();
          }
        },
      ),
      Shortcut(
        modifier: LogicalKeyboardKey.shiftLeft,
        key: LogicalKeyboardKey.keyW,
        action: () {
          logger.d('Closing dev tools');
          ArDriveDevTools.instance.closeDevTools();
        },
      ),
    ];

    return ShortcutHandler(
      shortcuts: shortcuts + (customShortcuts ?? []),
      child: child,
    );
  }
}
