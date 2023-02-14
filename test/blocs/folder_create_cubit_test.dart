import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_utils/fakes.dart';
import '../test_utils/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('FolderCreateCubit:', () {
    late DriveDao driveDao;
    late Database db;

    late ArweaveService arweave;
    late TurboService turboService;
    late ProfileCubit profileCubit;
    late FolderCreateCubit folderCreateCubit;

    setUp(() async {
      registerFallbackValue(ProfileStateFake());

      db = getTestDb();
      driveDao = db.driveDao;

      final configService = ConfigService(appFlavors: AppFlavors());
      final config = await configService.getConfig(
        localStore: await LocalKeyValueStore.getInstance(),
      );

      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);
      arweave = ArweaveService(
        Arweave(gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl!)),
        MockArDriveCrypto(),
      );
      turboService = DontUseTurbo();
      profileCubit = MockProfileCubit();

      folderCreateCubit = FolderCreateCubit(
        arweave: arweave,
        turboService: turboService,
        driveDao: driveDao,
        profileCubit: profileCubit,
        //TODO Mock or supply a driveId or parentFolderId
        driveId: '',
        parentFolderId: '',
      );
    });

    tearDown(() async {
      await db.close();
    });

    blocTest<FolderCreateCubit, FolderCreateState>(
      'does nothing when submitted without valid form',
      build: () => folderCreateCubit,
      act: (bloc) => bloc.submit(),
      expect: () => [],
    );
  });
}
