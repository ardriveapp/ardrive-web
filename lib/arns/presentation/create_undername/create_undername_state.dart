part of 'create_undername_bloc.dart';

sealed class CreateUndernameState extends Equatable {
  const CreateUndernameState();

  @override
  List<Object> get props => [];
}

final class CreateUndernameInitial extends CreateUndernameState {}

final class CreateUndernameLoading extends CreateUndernameState {}

final class CreateUndernameSuccess extends CreateUndernameState {
  final ARNSUndername undername;

  const CreateUndernameSuccess({required this.undername});

  @override
  List<Object> get props => [undername];
}

final class CreateUndernameFailure extends CreateUndernameState {
  @override
  List<Object> get props => [];
}
