import 'package:equatable/equatable.dart';

abstract class HideState extends Equatable {
  const HideState();
}

class InitialHideState extends HideState {
  const InitialHideState();

  @override
  List<Object?> get props => [];
}
