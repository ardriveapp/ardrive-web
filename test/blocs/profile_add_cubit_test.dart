import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../mocks.dart';
import '../utils.dart';

void main() {
  group('ProfileAddCubit', () {
    Database db;
    ProfileDao profileDao;
    ArweaveService arweave;

    Wallet newUserWallet;

    ProfileBloc profileBloc;
    ProfileAddCubit profileAddCubit;

    const fakePassword = '123';

    setUp(() {
      db = getTestDb();
      profileDao = db.profileDao;

      arweave = MockArweaveService();
      profileBloc = MockProfileBloc();

      newUserWallet = getTestWallet();

      profileAddCubit = ProfileAddCubit(
          profileBloc: profileBloc, profileDao: profileDao, arweave: arweave);

      when(arweave.getUniqueUserDriveEntityTxs(newUserWallet.address))
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
      expect: [
        ProfileAddPromptDetails(isNewUser: true),
      ],
      verify: (_) => verify(profileBloc.add(ProfileLoad(fakePassword))),
    );

    blocTest<ProfileAddCubit, ProfileAddState>(
      'does not attempt to add a profile when submitted without a valid form',
      build: () => profileAddCubit,
      act: (bloc) {
        bloc.form.value = {'password': ''};
        bloc.submit();
      },
      expect: [],
    );
  });
}
