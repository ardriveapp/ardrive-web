import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('ProfileUnlockCubit', () {
    ProfileDao profileDao;
    ProfileCubit profileCubit;
    ProfileUnlockCubit profileUnlockCubit;

    const rightPassword = 'right-password';
    const wrongPassword = 'wrong-password';

    setUp(() {
      profileDao = MockProfileDao();
      profileCubit = MockProfileBloc();

      when(profileDao.loadDefaultProfile(rightPassword))
          .thenAnswer((_) => Future.value());
      when(profileDao.loadDefaultProfile(wrongPassword))
          .thenThrow(ProfilePasswordIncorrectException());

      profileUnlockCubit = ProfileUnlockCubit(
          profileCubit: profileCubit, profileDao: profileDao);
    });

    blocTest<ProfileUnlockCubit, ProfileUnlockState>(
      'loads user profile when right password is used',
      build: () => profileUnlockCubit,
      act: (bloc) {
        bloc.form.value = {'password': rightPassword};
        bloc.submit();
      },
      verify: (bloc) =>
          verify(profileCubit.unlockDefaultProfile(rightPassword)),
    );

    blocTest<ProfileUnlockCubit, ProfileUnlockState>(
      'emits [] when submitted without valid form',
      build: () => profileUnlockCubit,
      act: (bloc) => bloc.submit(),
      expect: [],
    );

    blocTest<ProfileUnlockCubit, ProfileUnlockState>(
      'sets form "password-incorrect" error when incorrect password is used',
      build: () => profileUnlockCubit,
      act: (bloc) {
        bloc.form.value = {'password': wrongPassword};
        bloc.submit();
      },
      verify: (bloc) => expect(
          bloc.form.control('password').errors['password-incorrect'], isTrue),
    );
  });
}
