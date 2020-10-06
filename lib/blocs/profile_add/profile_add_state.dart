part of 'profile_add_cubit.dart';

@immutable
abstract class ProfileAddState extends Equatable {
  @override
  List<Object> get props => [];
}

class AddProfilePromptWallet extends ProfileAddState {}

class AddProfilePromptDetails extends ProfileAddState {
  final bool isNewUser;

  AddProfilePromptDetails({this.isNewUser});

  @override
  List<Object> get props => [isNewUser];
}
