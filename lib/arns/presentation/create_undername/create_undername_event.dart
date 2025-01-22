part of 'create_undername_bloc.dart';

sealed class CreateUndernameEvent extends Equatable {
  const CreateUndernameEvent();

  @override
  List<Object> get props => [];
}

final class CreateNewUndername extends CreateUndernameEvent {
  final String name;

  const CreateNewUndername(this.name);

  @override
  List<Object> get props => [name];
}
//
