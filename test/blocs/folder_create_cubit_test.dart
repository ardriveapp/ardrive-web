import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:arweave/arweave.dart';
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
    late TurboUploadService turboUploadService;
    late ProfileCubit profileCubit;
    late FolderCreateCubit folderCreateCubit;

    setUp(() async {
      registerFallbackValue(ProfileStateFake());

      db = getTestDb();
      driveDao = db.driveDao;

      final configService = ConfigService(
          appFlavors: AppFlavors(MockEnvFetcher()),
          configFetcher: MockConfigFetcher());
      final config = await configService.loadConfig();

      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);
      arweave = ArweaveService(
        Arweave(gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl!)),
        MockArDriveCrypto(),
      );
      turboUploadService = DontUseUploadService();
      profileCubit = MockProfileCubit();

      folderCreateCubit = FolderCreateCubit(
        arweave: arweave,
        turboUploadService: turboUploadService,
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
  });
}
