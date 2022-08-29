import 'dart:convert';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';
import '../test_utils/utils.dart';

void main() {
  group('ProfileAddCubit', () {
    late Database db;
    late ProfileDao profileDao;
    late ArweaveService arweave;

    late Wallet newUserWallet;

    late ProfileCubit profileCubit;
    late ProfileAddCubit profileAddCubit;

    const fakePassword = '123';

    setUp(() async {
      registerFallbackValue(ProfileStateFake());

      db = getTestDb();
      profileDao = db.profileDao;

      arweave = MockArweaveService();
      profileCubit = MockProfileCubit();

      newUserWallet = getTestWallet();

      profileAddCubit = ProfileAddCubit(
        profileCubit: profileCubit,
        profileDao: profileDao,
        arweave: arweave,
        context: MockContext(),
      );

      final walletAddress = await newUserWallet.getAddress();
      when(() => arweave.getUniqueUserDriveEntityTxs(walletAddress))
          .thenAnswer((_) => Future.value([]));
    });

    tearDown(() async {
      await db.close();
    });

    blocTest<ProfileAddCubit, ProfileAddState>(
      'add profile for new user',
      build: () => profileAddCubit,
      act: (bloc) async {
        await bloc.pickWallet(json.encode(newUserWallet.toJwk()));
        bloc.form.value = {'username': 'Bobby', 'password': fakePassword};
        await bloc.submit();
      },
      expect: () => [
        ProfileAddPromptDetails(isExistingUser: false),
      ],
      verify: (_) => verify(() =>
          profileCubit.unlockDefaultProfile(fakePassword, ProfileType.json)),
    );

    blocTest<ProfileAddCubit, ProfileAddState>(
      'does not attempt to add a profile when submitted without a valid form',
      build: () => profileAddCubit,
      act: (bloc) {
        bloc.form.value = {'password': ''};
        bloc.submit();
      },
      expect: () => [],
    );
  });
}
