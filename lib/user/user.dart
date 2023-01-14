import 'package:ardrive/entities/profile_types.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';

/// Class representing a user's profile.
///
abstract class User {
  late String password;
  late Wallet wallet;
  late String walletAddress;
  late BigInt walletBalance;
  late SecretKey cipherKey;
  late ProfileType profileType;

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
  late String password;

  @override
  late Wallet wallet;

  @override
  late String walletAddress;

  @override
  late BigInt walletBalance;

  @override
  late SecretKey cipherKey;

  @override
  late ProfileType profileType;

  _User({
    required this.password,
    required this.wallet,
    required this.walletAddress,
    required this.walletBalance,
    required this.cipherKey,
    required this.profileType,
  });
}
