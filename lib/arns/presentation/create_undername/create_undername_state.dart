part of 'create_undername_bloc.dart';

sealed class CreateUndernameState extends Equatable {
  const CreateUndernameState();

  @override
  List<Object> get props => [];
}

final class CreateUndernameInitial extends CreateUndernameState {}

final class CreateUndernameLoading extends CreateUndernameState {}

final class CreateUndernameSuccess extends CreateUndernameState {
  final ArNSNameModel nameModel;

  const CreateUndernameSuccess({required this.nameModel});

  @override
  List<Object> get props => [nameModel];
}

final class CreateUndernameFailure extends CreateUndernameState {
  final Exception exception;

  const CreateUndernameFailure({required this.exception});

  @override
  List<Object> get props => [exception];
}
