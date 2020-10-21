part of 'profile_add_cubit.dart';

@immutable
abstract class ProfileAddState extends Equatable {
  @override
  List<Object> get props => [];
}

class ProfileAddPromptWallet extends ProfileAddState {}

class ProfileAddUserStateLoadInProgress extends ProfileAddState {}

class ProfileAddOnboardingNewUser extends ProfileAddState {}

class ProfileAddPromptDetails extends ProfileAddState {
  final bool isExistingUser;

  ProfileAddPromptDetails({this.isExistingUser});

  @override
  List<Object> get props => [isExistingUser];
}
