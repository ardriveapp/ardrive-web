@Tags(['broken'])

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';
import '../test_utils/utils.dart';

void main() {
  group('ProfileAddCubit', () {
    late Database db;
    late ArweaveService arweave;

    late Wallet newUserWallet;

    late ProfileAddCubit profileAddCubit;
    late BiometricAuthentication biometricAuthentication;

    setUp(() async {
      registerFallbackValue(ProfileStateFake());

      db = getTestDb();
      biometricAuthentication = MockBiometricAuthentication();
      arweave = MockArweaveService();

      newUserWallet = getTestWallet();

      profileAddCubit = ProfileAddCubit(
        biometricAuthentication: biometricAuthentication,
      );

      final walletAddress = await newUserWallet.getAddress();
      when(() => arweave.getUniqueUserDriveEntityTxs(walletAddress))
          .thenAnswer((_) => Future.value([]));
    });

    tearDown(() async {
      await db.close();
    });

    test('promptForWallet emits ProfileAddPromptWallet', () async {
      await profileAddCubit.promptForWallet();
      expect(profileAddCubit.state, equals(ProfileAddPromptWallet()));
    });
  });
}
