@Tags(['broken'])

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart';
import 'package:drift/drift.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';
import '../test_utils/utils.dart';

class FakeEntity extends Fake implements Entity {}

void main() {
  group(
    'DriveCreateCubit',
    () {
      late Database db;
      late DriveDao driveDao;

      late ArweaveService arweave;
      late TurboUploadService turboUploadService;
      late DrivesCubit drivesCubit;
      late ProfileCubit profileCubit;
      late DriveCreateCubit driveCreateCubit;

      late Wallet wallet;

      const validDriveName = 'valid-drive-name';

      setUp(() async {
        wallet = getTestWallet();

        registerFallbackValue(DrivesStateFake());
        registerFallbackValue(ProfileStateFake());
        registerFallbackValue(DataBundle(blob: Uint8List.fromList([])));
        registerFallbackValue(wallet);
        registerFallbackValue(FakeEntity());

        db = getTestDb();
        driveDao = db.driveDao;
        AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);
        arweave = MockArweaveService();
        turboUploadService = DontUseUploadService();
        drivesCubit = MockDrivesCubit();
        profileCubit = MockProfileCubit();

        final walletAddress = await wallet.getAddress();
        final walletOwner = await wallet.getAddress();

        final keyBytes = Uint8List(32);
        fillBytesWithSecureRandom(keyBytes);

        when(() => profileCubit.state).thenReturn(
          ProfileLoggedIn(
            username: 'Test',
            password: '123',
            wallet: wallet,
            walletAddress: walletAddress,
            walletBalance: BigInt.from(10000001),
            cipherKey: SecretKey(keyBytes),
            useTurbo: turboUploadService.useTurboUpload,
          ),
        );

        when(() => profileCubit.logoutIfWalletMismatch()).thenAnswer(
          (invocation) => Future.value(false),
        );

        when(() => arweave.prepareBundledDataItem(any(), any())).thenAnswer(
          (invocation) => Future.value(
            DataItem.withBlobData(
              owner: walletOwner,
              data: Uint8List.fromList([]),
            ),
          ),
        );

        when(() => arweave.prepareEntityDataItem(any(), any())).thenAnswer(
          (invocation) => Future.value(
            DataItem.withBlobData(
              owner: walletOwner,
              data: Uint8List.fromList([]),
            ),
          ),
        );

        driveCreateCubit = DriveCreateCubit(
          arweave: arweave,
          turboUploadService: turboUploadService,
          driveDao: driveDao,
          drivesCubit: drivesCubit,
          profileCubit: profileCubit,
        );
      });

      tearDown(() async {
        await db.close();
      });

      blocTest<DriveCreateCubit, DriveCreateState>(
        'create public drive',
        build: () => driveCreateCubit,
        act: (bloc) async {
          bloc.form.value = {
            'name': validDriveName,
            'privacy': DrivePrivacy.public.name,
          };
          await bloc.submit('');
        },
        expect: () => [
          const DriveCreateInProgress(privacy: DrivePrivacy.public),
          const DriveCreateSuccess(privacy: DrivePrivacy.public),
        ],
        verify: (_) {},
      );

      blocTest<DriveCreateCubit, DriveCreateState>(
        'create private drive',
        build: () => driveCreateCubit,
        act: (bloc) async {
          bloc.form.value = {
            'name': validDriveName,
            'privacy': DrivePrivacy.private.name,
          };

          bloc.onPrivacyChanged();

          await bloc.submit('');
        },
        expect: () => [
          const DriveCreateInProgress(privacy: DrivePrivacy.public),
          const DriveCreateInProgress(privacy: DrivePrivacy.private),
          const DriveCreateSuccess(privacy: DrivePrivacy.private),
        ],
        verify: (_) {},
      );

      tearDown(() async {
        await db.close();
      });

      blocTest<DriveCreateCubit, DriveCreateState>(
        'create public drive',
        build: () => driveCreateCubit,
        act: (bloc) async {
          bloc.form.value = {
            'name': validDriveName,
            'privacy': DrivePrivacyTag.public,
          };
          await bloc.submit('');
        },
        expect: () => [
          const DriveCreateInProgress(
            privacy: DrivePrivacy.public,
          ),
          const DriveCreateSuccess(
            privacy: DrivePrivacy.public,
          ),
        ],
        verify: (_) {},
      );

      blocTest<DriveCreateCubit, DriveCreateState>(
        'create private drive',
        build: () => driveCreateCubit,
        act: (bloc) async {
          bloc.form.value = {
            'name': validDriveName,
            'privacy': DrivePrivacyTag.private,
          };

          bloc.onPrivacyChanged();

          await bloc.submit('');
        },
        expect: () => [
          const DriveCreateInProgress(privacy: DrivePrivacy.public),
          const DriveCreateInProgress(privacy: DrivePrivacy.private),
          const DriveCreateSuccess(privacy: DrivePrivacy.private),
        ],
        verify: (_) {},
      );

      blocTest<DriveCreateCubit, DriveCreateState>(
        'does nothing when submitted without valid form',
        build: () => driveCreateCubit,
        act: (bloc) => bloc.submit(''),
        expect: () => [],
      );
    },
  );
}
