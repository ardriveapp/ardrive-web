import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';
import '../test_utils/utils.dart';

void main() {
  group('FolderCreateCubit:', () {
    late DriveDao driveDao;
    late Database db;

    late ArweaveService arweave;
    late ProfileCubit profileCubit;
    late FolderCreateCubit folderCreateCubit;

    setUp(() async {
      registerFallbackValue(ProfileStatefake());

      db = getTestDb();
      driveDao = db.driveDao;

      final configService = ConfigService();
      final config = await configService.getConfig();

      arweave = ArweaveService(
          Arweave(gatewayUrl: Uri.parse(config.defaultArweaveGatewayUrl!)));
      profileCubit = MockProfileCubit();

      folderCreateCubit = FolderCreateCubit(
        arweave: arweave,
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
