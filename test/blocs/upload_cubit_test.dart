import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../utils/fakes.dart';
import '../utils/mocks.dart';
import '../utils/utils.dart';

void main() {
  late ProfileCubit profileCubit;
  late UploadCubit uploadCubit;

  late ArweaveService arweave;
  late PstService pstService;

  late Database db;
  late DriveDao driveDao;

  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';

  group('UploadCubitTest', () {
    setUp(() {
      registerFallbackValue(ProfileStatefake());

      arweave = MockArweaveService();
      pstService = PstService();

      db = getTestDb();
      driveDao = db.driveDao;

      profileCubit = MockProfileCubit();
      uploadCubit = UploadCubit(
        profileCubit: profileCubit,
        arweave: arweave,
        driveDao: driveDao,
        driveId: driveId,
        files: [],
        folderId: rootFolderId,
        pst: pstService,
      );
    });
    blocTest('UploadCubit prepares file', build: () => uploadCubit);
  });
}
