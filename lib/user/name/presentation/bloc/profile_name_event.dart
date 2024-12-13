part of 'profile_name_bloc.dart';

sealed class ProfileNameEvent extends Equatable {
  const ProfileNameEvent();

  @override
  List<Object> get props => [];
}

final class RefreshProfileName extends ProfileNameEvent {}

final class LoadProfileName extends ProfileNameEvent {}

final class LoadProfileNameAnonymous extends ProfileNameEvent {
  final String walletAddress;

  const LoadProfileNameAnonymous(this.walletAddress);
}

final class CleanProfileName extends ProfileNameEvent {
  const CleanProfileName();
}
