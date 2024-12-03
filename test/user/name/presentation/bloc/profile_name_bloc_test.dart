import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/user.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockARNSRepository extends Mock implements ARNSRepository {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockCurrentUser extends Mock implements User {}

void main() {
  late MockARNSRepository arnsRepository;
  late MockArDriveAuth auth;
  late MockCurrentUser currentUser;
  const testWalletAddress = '0x123456789';
  const testPrimaryName = 'test.arweave';

  setUp(() {
    arnsRepository = MockARNSRepository();
    auth = MockArDriveAuth();
    currentUser = MockCurrentUser();

    when(() => auth.currentUser).thenReturn(currentUser);
    when(() => currentUser.walletAddress).thenReturn(testWalletAddress);
  });

  group('ProfileNameBloc', () {
    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits [ProfileNameLoading, ProfileNameLoaded] when LoadProfileName is successful',
      build: () {
        when(() =>
                arnsRepository.getPrimaryName(testWalletAddress, update: false))
            .thenAnswer((_) async => testPrimaryName);
        return ProfileNameBloc(arnsRepository, auth);
      },
      act: (bloc) => bloc.add(LoadProfileName()),
      expect: () => [
        const ProfileNameLoading(testWalletAddress),
        const ProfileNameLoaded(testPrimaryName, testWalletAddress),
      ],
    );

    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits [ProfileNameLoaded] when RefreshProfileName is successful',
      build: () {
        when(() =>
                arnsRepository.getPrimaryName(testWalletAddress, update: true))
            .thenAnswer((_) async => testPrimaryName);
        return ProfileNameBloc(arnsRepository, auth);
      },
      act: (bloc) => bloc.add(RefreshProfileName()),
      expect: () => [
        const ProfileNameLoaded(testPrimaryName, testWalletAddress),
      ],
    );

    blocTest<ProfileNameBloc, ProfileNameState>(
      'truncates primary name when longer than 20 characters',
      build: () {
        const longName = 'verylongprimarynamethatshouldbecutoff.arweave';
        when(() =>
                arnsRepository.getPrimaryName(testWalletAddress, update: false))
            .thenAnswer((_) async => longName);
        return ProfileNameBloc(arnsRepository, auth);
      },
      act: (bloc) => bloc.add(LoadProfileName()),
      expect: () => [
        const ProfileNameLoading(testWalletAddress),
        const ProfileNameLoaded('verylongprimarynamet', testWalletAddress),
      ],
    );

    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits [ProfileNameLoading, ProfileNameLoadedWithWalletAddress] when getPrimaryName throws PrimaryNameNotFoundException',
      build: () {
        when(() =>
                arnsRepository.getPrimaryName(testWalletAddress, update: false))
            .thenThrow(PrimaryNameNotFoundException('Test error'));
        return ProfileNameBloc(arnsRepository, auth);
      },
      act: (bloc) => bloc.add(LoadProfileName()),
      expect: () => [
        const ProfileNameLoading(testWalletAddress),
        const ProfileNameLoadedWithWalletAddress(testWalletAddress),
      ],
    );

    blocTest<ProfileNameBloc, ProfileNameState>(
      'emits [ProfileNameLoading, ProfileNameLoadedWithWalletAddress] when getPrimaryName throws general error',
      build: () {
        when(() =>
                arnsRepository.getPrimaryName(testWalletAddress, update: false))
            .thenThrow(Exception('Test error'));
        return ProfileNameBloc(arnsRepository, auth);
      },
      act: (bloc) => bloc.add(LoadProfileName()),
      expect: () => [
        const ProfileNameLoading(testWalletAddress),
        const ProfileNameLoadedWithWalletAddress(testWalletAddress),
      ],
    );
  });
}
