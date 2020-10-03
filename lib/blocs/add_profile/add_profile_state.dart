part of 'add_profile_cubit.dart';

@immutable
abstract class AddProfileState {}

class AddProfilePromptWallet extends AddProfileState {}

class AddProfilePromptDetails extends AddProfileState {
  final bool isNewUser;

  AddProfilePromptDetails({this.isNewUser});
}
