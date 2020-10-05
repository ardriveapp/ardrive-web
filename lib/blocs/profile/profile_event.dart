part of 'profile_bloc.dart';

@immutable
abstract class ProfileEvent extends Equatable {
  @override
  List<Object> get props => [];
}

class ProfileCheckDefault extends ProfileEvent {}

class ProfileLoad extends ProfileEvent {
  final String password;

  ProfileLoad(this.password);

  @override
  List<Object> get props => [password];
}

class Logout extends ProfileEvent {}
