part of 'user_bloc.dart';

@immutable
abstract class UserEvent {}

class AttemptLogin extends UserEvent {
  final Map<String, dynamic> jwk;

  AttemptLogin(this.jwk);
}

class Logout extends UserEvent {}
