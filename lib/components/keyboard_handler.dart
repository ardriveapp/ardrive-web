import 'package:ardrive/blocs/blocs.dart';
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
  var checkboxEnabled = false;
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
                if (event.isKeyPressed(LogicalKeyboardKey.shiftLeft) ||
                    event.isKeyPressed(LogicalKeyboardKey.shiftRight)) {
                  if (event is RawKeyDownEvent) {
                    setState(() => checkboxEnabled = true);
                  }
                } else {
                  setState(() => checkboxEnabled = false);
                }
                context.read<KeyboardListenerBloc>().add(
                      KeyboardListenerUpdateCtrlMetaPressed(
                        isPressed: checkboxEnabled,
                      ),
                    );
              },
              child: widget.child);
        },
      ),
    );
  }
}
