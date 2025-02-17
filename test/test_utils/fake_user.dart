import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/user/user.dart';
import 'package:cryptography/cryptography.dart';

import 'utils.dart';

final fakeUserJson = User(
  password: 'password',
  wallet: getTestWallet(),
  walletAddress: 'address',
  walletBalance: BigInt.zero,
  cipherKey: SecretKey([1, 2, 3]),
  profileType: ProfileType.json,
  errorFetchingIOTokens: false,
);

final fakeUserArConnect = User(
  password: 'password',
  wallet: getTestWallet(),
  walletAddress: 'address',
  walletBalance: BigInt.zero,
  cipherKey: SecretKey([1, 2, 3]),
  profileType: ProfileType.arConnect,
  errorFetchingIOTokens: false,
);
