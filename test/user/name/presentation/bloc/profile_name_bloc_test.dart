import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/name/domain/repository/profile_logo_repository.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/user.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockARNSRepository extends Mock implements ARNSRepository {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockCurrentUser extends Mock implements User {}

class MockProfileLogoRepository extends Mock implements ProfileLogoRepository {}

void main() {
  late MockARNSRepository arnsRepository;
  late MockArDriveAuth auth;
  late MockCurrentUser currentUser;
  late MockProfileLogoRepository profileLogoRepository;
  const testWalletAddress = '0x123456789';

  setUp(() {
    arnsRepository = MockARNSRepository();
    auth = MockArDriveAuth();
    currentUser = MockCurrentUser();
    profileLogoRepository = MockProfileLogoRepository();
    when(() => auth.currentUser).thenReturn(currentUser);
    when(() => currentUser.walletAddress).thenReturn(testWalletAddress);
  });

  group('ProfileNameBloc', () {
    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits [ProfileNameLoading, ProfileNameLoadedWithWalletAddress] on LoadProfileName when no cross-chain name is found',
      build: () {
        return ProfileNameBloc(arnsRepository, profileLogoRepository, auth);
      },
      act: (bloc) => bloc.add(LoadProfileName()),
      expect: () => [
        const ProfileNameLoading(testWalletAddress),
        const ProfileNameLoadedWithWalletAddress(testWalletAddress),
      ],
    );

    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits [ProfileNameLoadedWithWalletAddress] on RefreshProfileName when no cross-chain name is found',
      build: () {
        return ProfileNameBloc(arnsRepository, profileLogoRepository, auth);
      },
      act: (bloc) => bloc.add(RefreshProfileName()),
      expect: () => [
        const ProfileNameLoadedWithWalletAddress(testWalletAddress),
      ],
    );

    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits [ProfileNameInitial] on CleanProfileName',
      build: () {
        return ProfileNameBloc(arnsRepository, profileLogoRepository, auth);
      },
      act: (bloc) => bloc.add(const CleanProfileName()),
      expect: () => [
        const ProfileNameInitial(null),
      ],
    );
  });
}
