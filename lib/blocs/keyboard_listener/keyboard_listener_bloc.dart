import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'keyboard_listener_event.dart';
part 'keyboard_listener_state.dart';

class KeyboardListenerBloc
    extends Bloc<KeyboardListenerEvent, KeyboardListenerState> {
  KeyboardListenerBloc() : super(KeyboardListenerInitial()) {
    on<KeyboardListenerEvent>((event, emit) {
      if (event is KeyboardListenerUpdateCtrlMetaPressed) {
        emit(KeyboardListenerCtrlMetaPressed(isPressed: event.isPressed));
      }
    });
  }
}
