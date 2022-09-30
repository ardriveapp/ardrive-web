part of 'keyboard_listener_bloc.dart';

abstract class KeyboardListenerState extends Equatable {
  const KeyboardListenerState();

  @override
  List<Object> get props => [];
}

class KeyboardListenerInitial extends KeyboardListenerState {}

class KeyboardListenerCtrlMetaPressed extends KeyboardListenerState {
  final bool isPressed;
  const KeyboardListenerCtrlMetaPressed({
    required this.isPressed,
  });

  @override
  List<Object> get props => [isPressed];
}
