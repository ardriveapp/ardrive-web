part of 'profile_bloc.dart';

@immutable
abstract class ProfileEvent {}

class AttemptLogin extends ProfileEvent {
  final Map<String, dynamic> jwk;

  AttemptLogin(this.jwk);
}

class Logout extends ProfileEvent {}
