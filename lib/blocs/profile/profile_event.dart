part of 'profile_bloc.dart';

@immutable
abstract class ProfileEvent {}

class ProfileCheckDefault extends ProfileEvent {}

class ProfileLoad extends ProfileEvent {
  final String password;

  ProfileLoad(this.password);
}

class ProfileAdd extends ProfileEvent {
  final String username;
  final String password;
  final Map<String, dynamic> jwk;

  ProfileAdd(this.username, this.password, this.jwk);
}

class Logout extends ProfileEvent {}
