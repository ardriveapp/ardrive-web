import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/download_wallet/bloc/download_wallet_bloc.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/fake_user.dart';
import '../../../test_utils/utils.dart';

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockArDriveIOUtils extends Mock implements ArDriveIOUtils {}

void main() {
  late MockArDriveAuth mockArDriveAuth;
  late MockArDriveIOUtils mockArDriveIOUtils;
  late DownloadWalletBloc downloadWalletBloc;

  setUp(() {
    mockArDriveAuth = MockArDriveAuth();
    mockArDriveIOUtils = MockArDriveIOUtils();
    downloadWalletBloc = DownloadWalletBloc(
      ardriveAuth: mockArDriveAuth,
      ardriveIOUtils: mockArDriveIOUtils,
    );

    registerFallbackValue(getTestWallet());
  });

  blocTest<DownloadWalletBloc, DownloadWalletState>(
    'emits [DownloadWalletLoading, DownloadWalletSuccess] when wallet download is successful',
    build: () {
      final userJson = fakeUserJson;

      when(() => mockArDriveAuth.unlockUser(password: any(named: 'password')))
          .thenAnswer((_) async => userJson);
      when(() => mockArDriveAuth.currentUser).thenReturn(userJson);

      when(() => mockArDriveIOUtils.downloadWalletAsJsonFile(
          wallet: any(named: 'wallet'))).thenAnswer((_) async => true);

      return DownloadWalletBloc(
        ardriveAuth: mockArDriveAuth,
        ardriveIOUtils: mockArDriveIOUtils,
      );
    },
    act: (bloc) => bloc.add(const DownloadWallet('password')),
    expect: () => [
      DownloadWalletLoading(),
      const DownloadWalletSuccess(),
    ],
  );

  test(
      'DownloadWalletBloc should emit DownloadWalletLoading and DownloadWalletFailure on failure',
      () async {
    when(() => mockArDriveAuth.unlockUser(password: any(named: 'password')))
        .thenThrow(Exception('Failed to unlock user'));

    final expectedStates = [
      DownloadWalletLoading(),
      DownloadWalletWrongPassword(),
    ];

    expectLater(
      downloadWalletBloc.stream,
      emitsInOrder(expectedStates),
    );

    // Dispatch DownloadWallet event
    downloadWalletBloc.add(const DownloadWallet('password'));
  });
}
