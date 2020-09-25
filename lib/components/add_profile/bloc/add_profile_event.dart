part of 'add_profile_bloc.dart';

@immutable
abstract class AddProfileEvent {}

@immutable
class AddProfileAttempted extends AddProfileEvent {
  final String username;
  final String password;
  final String walletJson;

  AddProfileAttempted({this.username, this.password, this.walletJson});
}
