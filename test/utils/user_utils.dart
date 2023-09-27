import 'package:ardrive/entities/profile_source.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/utils.dart';

void main() {
  final auth = MockArDriveAuth();

  group('isDriveOwner', () {
    test(
        'should return true when the wallet address is the same of the current user',
        () {
      final wallet = getTestWallet();

      final user = User(
        password: 'password',
        wallet: wallet,
        walletAddress: 'address',
        walletBalance: BigInt.zero,
        cipherKey: SecretKey([1, 2, 3]),
        profileType: ProfileType.json,
        profileSource: ProfileSource(type: ProfileSourceType.standalone),
      );
      // arrange
      when(() => auth.currentUser).thenReturn(user);

      // act
      final result = isDriveOwner(auth, user.walletAddress);

      // assert
      expect(result, true);
    });

    test(
        'should return false when the wallet address is not the same of the current user',
        () {
      final wallet = getTestWallet();

      final user = User(
        password: 'password',
        wallet: wallet,
        walletAddress: 'address',
        walletBalance: BigInt.zero,
        cipherKey: SecretKey([1, 2, 3]),
        profileType: ProfileType.json,
        profileSource: ProfileSource(type: ProfileSourceType.standalone),
      );
      // arrange
      when(() => auth.currentUser).thenReturn(user);

      // act
      final result = isDriveOwner(auth, 'other address');

      // assert
      expect(result, false);
    });

    test('should return false when the current user is null', () {
      // arrange
      when(() => auth.currentUser).thenReturn(null);

      // act
      final result = isDriveOwner(auth, 'other address');

      // assert
      expect(result, false);
    });
  });
}
