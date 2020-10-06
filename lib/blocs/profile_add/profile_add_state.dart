part of 'profile_add_cubit.dart';

@immutable
abstract class ProfileAddState extends Equatable {
  @override
  List<Object> get props => [];
}

class ProfileAddPromptWallet extends ProfileAddState {}

class ProfileAddPromptDetails extends ProfileAddState {
  final bool isNewUser;

  ProfileAddPromptDetails({this.isNewUser});

  @override
  List<Object> get props => [isNewUser];
}
