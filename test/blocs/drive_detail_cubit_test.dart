import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:cryptography/cryptography.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../mocks.dart';
import '../utils.dart';

void main() {
  group('DriveDetailCubit:', () {
    Database db;
    DriveDao driveDao;

    ProfileBloc profileBloc;
    UploadBloc uploadBloc;
    DriveDetailCubit driveDetailCubit;

    const mockDriveId = 'mock-drive-id';

    setUp(() {
      db = getTestDb();
      driveDao = db.driveDao;

      profileBloc = MockProfileBloc();
      uploadBloc = MockUploadBloc();

      when(profileBloc.state).thenReturn(
        ProfileLoaded(
          password: '123',
          wallet: getTestWallet(),
          cipherKey: SecretKey.randomBytes(32),
        ),
      );

      driveDetailCubit = DriveDetailCubit(
        driveId: mockDriveId,
        profileBloc: profileBloc,
        uploadBloc: uploadBloc,
        driveDao: driveDao,
      );
    });

    tearDown(() async {
      await db.close();
    });
  });
}
