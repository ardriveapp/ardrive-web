part of 'profile_add_cubit.dart';

@immutable
abstract class ProfileAddState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ProfileAddPromptWallet extends ProfileAddState {}

/// The user's profile usage is being checked for.
class ProfileAddUserStateLoadInProgress extends ProfileAddState {}

class ProfileAddOnboardingNewUser extends ProfileAddState {}

class ProfileAddPromptDetails extends ProfileAddState {
  final bool? isExistingUser;

  ProfileAddPromptDetails({this.isExistingUser});

  @override
  List<Object?> get props => [isExistingUser];
}

/// The user's profile details is being validated and added.
class ProfileAddInProgress extends ProfileAddState {}

class ProfileAddFailiure extends ProfileAddState {}

class ProfileAddWalletMismatch extends ProfileAddState {}
