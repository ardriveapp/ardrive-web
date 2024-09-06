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
  abstract final String? ioTokens;

  factory User({
    required String password,
    required Wallet wallet,
    required String walletAddress,
    required BigInt walletBalance,
    required SecretKey cipherKey,
    required ProfileType profileType,
    String? ioTokens,
  }) =>
      _User(
        password: password,
        wallet: wallet,
        walletAddress: walletAddress,
        walletBalance: walletBalance,
        cipherKey: cipherKey,
        profileType: profileType,
        ioTokens: ioTokens,
      );

  User copyWith({
    String? password,
    Wallet? wallet,
    String? walletAddress,
    BigInt? walletBalance,
    SecretKey? cipherKey,
    ProfileType? profileType,
    String? ioTokens,
  });
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
  @override
  final String? ioTokens;

  _User({
    required this.password,
    required this.wallet,
    required this.walletAddress,
    required this.walletBalance,
    required this.cipherKey,
    required this.profileType,
    this.ioTokens,
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
  String toString() => 'User { walletAddress: $walletAddress }';

  @override
  User copyWith({
    String? password,
    Wallet? wallet,
    String? walletAddress,
    BigInt? walletBalance,
    SecretKey? cipherKey,
    ProfileType? profileType,
    String? ioTokens,
  }) {
    return _User(
      password: password ?? this.password,
      wallet: wallet ?? this.wallet,
      walletAddress: walletAddress ?? this.walletAddress,
      walletBalance: walletBalance ?? this.walletBalance,
      cipherKey: cipherKey ?? this.cipherKey,
      profileType: profileType ?? this.profileType,
      ioTokens: ioTokens ?? this.ioTokens,
    );
  }
}
