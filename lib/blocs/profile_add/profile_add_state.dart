part of 'profile_add_cubit.dart';

@immutable
abstract class ProfileAddState {}

class AddProfilePromptWallet extends ProfileAddState {}

class AddProfilePromptDetails extends ProfileAddState {
  final bool isNewUser;

  AddProfilePromptDetails({this.isNewUser});
}
