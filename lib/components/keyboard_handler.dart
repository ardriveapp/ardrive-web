import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/dev_tools/shortcut_handler.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/extensions.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class KeyboardHandler extends StatefulWidget {
  final Widget child;
  const KeyboardHandler({Key? key, required this.child}) : super(key: key);

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
          return RawKeyboardListener(
            focusNode: _focusTable,
            autofocus: true,
            onKey: (event) async {
              // detect if ctrl + v or cmd + v is pressed
              if (await isCtrlOrMetaKeyPressed(event)) {
                if (event is RawKeyDownEvent) {
                  setState(() => ctrlMetaPressed = true);
                }
              } else {
                setState(() => ctrlMetaPressed = false);
              }

              if (!mounted) return;
              context.read<KeyboardListenerBloc>().add(
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

Future<bool> isCtrlOrMetaKeyPressed(RawKeyEvent event) async {
  try {
    final userAgent = (await DeviceInfoPlugin().webBrowserInfo).userAgent;
    late bool ctrlMetaKeyPressed;
    if (userAgent != null && isApple(userAgent)) {
      ctrlMetaKeyPressed = event.isKeyPressed(LogicalKeyboardKey.metaLeft) ||
          event.isKeyPressed(LogicalKeyboardKey.metaRight);
    } else {
      ctrlMetaKeyPressed = event.isKeyPressed(LogicalKeyboardKey.controlLeft) ||
          event.isKeyPressed(LogicalKeyboardKey.controlRight);
    }
    return ctrlMetaKeyPressed;
  } catch (e) {
    'Unable to compute platform'.logError();
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
    Key? key,
    required this.child,
    this.customShortcuts,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Define the shortcuts and their actions
    final List<Shortcut> shortcuts = [
      Shortcut(
        modifier: LogicalKeyboardKey.shiftLeft,
        key: LogicalKeyboardKey.keyQ,
        action: () {
          if (context.read<ConfigService>().flavor == Flavor.development) {
            logger.i('Opening dev tools');
            ArDriveDevTools.instance.showDevTools();
          }
        },
      ),
      Shortcut(
        modifier: LogicalKeyboardKey.shiftLeft,
        key: LogicalKeyboardKey.keyW,
        action: () {
          if (context.read<ConfigService>().flavor == Flavor.development) {
            logger.i('Closing dev tools');
            ArDriveDevTools.instance.closeDevTools();
          }
        },
      ),
    ];

    return ShortcutHandler(
      shortcuts: shortcuts + (customShortcuts ?? []),
      child: child,
    );
  }
}
