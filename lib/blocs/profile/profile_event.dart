part of 'profile_bloc.dart';

@immutable
abstract class ProfileEvent {}

class ProfileCheckDefault extends ProfileEvent {}

class ProfileLoad extends ProfileEvent {
  final String password;

  ProfileLoad(this.password);
}

class Logout extends ProfileEvent {}
