import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:drift/drift.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/utils.dart';

void main() {
  group('DriveDetailCubit:', () {
    late Database db;
    late DriveDao driveDao;

    late ProfileCubit profileCubit;
    late DriveDetailCubit driveDetailCubit;
    late AppConfig config;
    const mockDriveId = 'mock-drive-id';

    setUp(() async {
      db = getTestDb();
      driveDao = db.driveDao;
      config = MockConfig();
      profileCubit = MockProfileCubit();

      final keyBytes = Uint8List(32);
      fillBytesWithSecureRandom(keyBytes);
      final wallet = getTestWallet();
      when(() => profileCubit.state).thenReturn(
        ProfileLoggedIn(
            username: '',
            password: '123',
            wallet: wallet,
            cipherKey: SecretKey(keyBytes),
            walletAddress: await wallet.getAddress(),
            walletBalance: BigInt.one,
            useTurbo: false,),
      );

      driveDetailCubit = DriveDetailCubit(
        driveId: mockDriveId,
        profileCubit: profileCubit,
        driveDao: driveDao,
        config: config,
      );
    });

    tearDown(() async {
      await db.close();
    });
  });
}
