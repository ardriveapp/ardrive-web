part of 'profile_name_bloc.dart';

sealed class ProfileNameState extends Equatable {
  const ProfileNameState();

  abstract final String? walletAddress;

  @override
  List<Object?> get props => [walletAddress];
}

final class ProfileNameInitial extends ProfileNameState {
  const ProfileNameInitial(this.walletAddress);

  @override
  final String? walletAddress;
}

final class ProfileNameLoading extends ProfileNameState {
  @override
  final String walletAddress;

  const ProfileNameLoading(this.walletAddress);
}

final class ProfileNameLoaded extends ProfileNameState {
  final PrimaryNameDetails primaryNameDetails;

  const ProfileNameLoaded(this.primaryNameDetails, this.walletAddress);

  @override
  final String walletAddress;

  @override
  List<Object> get props => [primaryNameDetails, walletAddress];
}

// if fails to load primary name, show current wallet address
final class ProfileNameLoadedWithWalletAddress extends ProfileNameState {
  @override
  final String walletAddress;

  const ProfileNameLoadedWithWalletAddress(this.walletAddress);
}
