import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/profileTypes.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../utils/utils.dart';

void main() {
  group('ProfileUnlockCubit', () {
    late ProfileDao profileDao;
    late ProfileCubit profileCubit;
    late ProfileUnlockCubit profileUnlockCubit;
    late ArweaveService arweave;

    const rightPassword = 'right-password';
    const wrongPassword = 'wrong-password';

    setUp(() {
      profileDao = MockProfileDao();
      profileCubit = MockProfileCubit();
      arweave = MockArweaveService();

      when(profileDao.loadDefaultProfile(rightPassword))
          .thenAnswer((_) => Future.value());
      when(profileDao.loadDefaultProfile(wrongPassword))
          .thenThrow(ProfilePasswordIncorrectException());

      profileUnlockCubit = ProfileUnlockCubit(
        profileCubit: profileCubit,
        profileDao: profileDao,
        arweave: arweave,
      );
    });

    blocTest<ProfileUnlockCubit, ProfileUnlockState>(
      'loads user profile when right password is used',
      build: () => profileUnlockCubit,
      act: (bloc) {
        bloc.form.value = {'password': rightPassword};
        bloc.submit();
      },
      verify: (bloc) => verify(
          profileCubit.unlockDefaultProfile(rightPassword, ProfileType.JSON)),
    );

    blocTest<ProfileUnlockCubit, ProfileUnlockState>(
      'emits [] when submitted without valid form',
      build: () => profileUnlockCubit,
      act: (bloc) => bloc.submit(),
      expect: () => [],
    );

    blocTest<ProfileUnlockCubit, ProfileUnlockState>(
      'sets form "${AppValidationMessage.passwordIncorrect}" error when incorrect password is used',
      build: () => profileUnlockCubit,
      act: (bloc) {
        bloc.form.value = {'password': wrongPassword};
        bloc.submit();
      },
      verify: (bloc) => expect(
          bloc.form
              .control('password')
              .errors[AppValidationMessage.passwordIncorrect],
          isTrue),
    );
  });
}
