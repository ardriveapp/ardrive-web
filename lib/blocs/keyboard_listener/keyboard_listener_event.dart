part of 'keyboard_listener_bloc.dart';

abstract class KeyboardListenerEvent extends Equatable {
  const KeyboardListenerEvent();
}

class KeyboardListenerUpdateCtrlMetaPressed extends KeyboardListenerEvent {
  final bool isPressed;
  const KeyboardListenerUpdateCtrlMetaPressed({
    required this.isPressed,
  });

  @override
  List<Object> get props => [isPressed];
}
