import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/user.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockCurrentUser extends Mock implements User {}

void main() {
  late MockArDriveAuth auth;
  late MockCurrentUser currentUser;
  const testArweaveAddress = 'fOVzBRTBnyt4VrUUYadBH8yras_-jhgpmNgg-5b3vEw';

  setUp(() {
    auth = MockArDriveAuth();
    currentUser = MockCurrentUser();
    when(() => auth.currentUser).thenReturn(currentUser);
    when(() => currentUser.walletAddress).thenReturn(testArweaveAddress);
    when(() => currentUser.sourceWalletAddress).thenReturn(null);
  });

  group('ProfileNameBloc', () {
    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits [ProfileNameLoading, ProfileNameLoadedWithWalletAddress] for Arweave-only user (no .sol/.eth)',
      build: () => ProfileNameBloc(auth),
      act: (bloc) => bloc.add(LoadProfileName()),
      expect: () => [
        const ProfileNameLoading(testArweaveAddress),
        const ProfileNameLoadedWithWalletAddress(testArweaveAddress),
      ],
    );

    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits [ProfileNameLoading, ProfileNameLoadedWithWalletAddress] on refresh',
      build: () => ProfileNameBloc(auth),
      act: (bloc) => bloc.add(RefreshProfileName()),
      expect: () => [
        const ProfileNameLoading(testArweaveAddress),
        const ProfileNameLoadedWithWalletAddress(testArweaveAddress),
      ],
    );

    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits ProfileNameLoadedWithWalletAddress for pre-login with Arweave address',
      build: () => ProfileNameBloc(auth),
      act: (bloc) =>
          bloc.add(LoadProfileNameBeforeLogin(testArweaveAddress)),
      expect: () => [
        const ProfileNameLoading(testArweaveAddress),
        const ProfileNameLoadedWithWalletAddress(testArweaveAddress),
      ],
    );

    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits ProfileNameInitial when CleanProfileName is dispatched',
      build: () => ProfileNameBloc(auth),
      act: (bloc) => bloc.add(const CleanProfileName()),
      expect: () => [
        const ProfileNameInitial(null),
      ],
    );
  });
}
