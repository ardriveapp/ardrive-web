part of 'profile_unlock_cubit.dart';

@immutable
abstract class ProfileUnlockState extends Equatable {
  @override
  List<Object> get props => [];
}

class ProfileUnlockInitializing extends ProfileUnlockState {}

class ProfileUnlockInitial extends ProfileUnlockState {
  final String username;

  ProfileUnlockInitial({this.username});

  @override
  List<Object> get props => [username];
}

class ProfileUnlockFailure extends ProfileUnlockState {}
