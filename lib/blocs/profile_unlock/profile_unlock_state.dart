part of 'profile_unlock_cubit.dart';

@immutable
abstract class ProfileUnlockState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ProfileUnlockInitializing extends ProfileUnlockState {}

class ProfileUnlockInitial extends ProfileUnlockState {
  ProfileUnlockInitial({
    this.username,
    this.autoFocus = false,
  });

  final String? username;
  final bool autoFocus;

  @override
  List<Object?> get props => [username, autoFocus];
}

class ProfileUnlockWithBiometrics extends ProfileUnlockState {}

class ProfileUnlockFailure extends ProfileUnlockState {}

class ProfileUnlockBiometricFailure extends ProfileUnlockState {
  ProfileUnlockBiometricFailure(this.exception);

  final BiometricException exception;
}
