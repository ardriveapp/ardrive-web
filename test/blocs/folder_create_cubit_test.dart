import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../utils/fakes.dart';
import '../utils/utils.dart';

void main() {
  group('FolderCreateCubit:', () {
    late DriveDao driveDao;
    late Database db;

    late ArweaveService arweave;
    late ProfileCubit profileCubit;
    late FolderCreateCubit folderCreateCubit;

    const testGatewayURL = 'https://arweave.net';

    setUp(() async {
      registerFallbackValue(ProfileStatefake());

      db = getTestDb();
      driveDao = db.driveDao;

      arweave = ArweaveService(Arweave(gatewayUrl: Uri.parse(testGatewayURL)));
      profileCubit = MockProfileCubit();

      folderCreateCubit = FolderCreateCubit(
        arweave: arweave,
        driveDao: driveDao,
        profileCubit: profileCubit,
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