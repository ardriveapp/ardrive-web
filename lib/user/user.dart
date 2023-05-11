import 'package:ardrive/entities/profile_types.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';

/// Class representing a user's profile.
///
abstract class User with EquatableMixin {
  late final String password;
  late final Wallet wallet;
  late final String walletAddress;
  late final BigInt walletBalance;
  late final SecretKey cipherKey;
  late final ProfileType profileType;

  factory User({
    required String password,
    required Wallet wallet,
    required String walletAddress,
    required BigInt walletBalance,
    required SecretKey cipherKey,
    required ProfileType profileType,
  }) =>
      _User(
        password: password,
        wallet: wallet,
        walletAddress: walletAddress,
        walletBalance: walletBalance,
        cipherKey: cipherKey,
        profileType: profileType,
      );
}

class _User implements User {
  @override
  late final String password;
  @override
  late final Wallet wallet;
  @override
  late final String walletAddress;
  @override
  late final BigInt walletBalance;
  @override
  late final SecretKey cipherKey;
  @override
  late final ProfileType profileType;

  _User({
    required this.password,
    required this.wallet,
    required this.walletAddress,
    required this.walletBalance,
    required this.cipherKey,
    required this.profileType,
  });

  @override
  List<Object> get props => [
        password,
        walletAddress,
        walletBalance,
        cipherKey,
        profileType,
        wallet,
      ];

  @override
  bool? get stringify => true;

  @override
  toString() => 'User { walletAddress: $walletAddress }';
}
