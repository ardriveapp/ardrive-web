import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:test/test.dart';

import '../mocks.dart';
import '../utils.dart';

void main() {
  group('FolderCreateCubit:', () {
    Database db;
    DriveDao driveDao;

    ArweaveService arweave;
    DriveDetailCubit driveDetailCubit;
    ProfileBloc profileBloc;
    FolderCreateCubit folderCreateCubit;

    setUp(() {
      db = getTestDb();
      driveDao = db.driveDao;

      arweave = ArweaveService(Arweave());
      driveDetailCubit = MockDriveDetailCubit();
      profileBloc = MockProfileBloc();

      folderCreateCubit = FolderCreateCubit(
        arweave: arweave,
        driveDao: driveDao,
        driveDetailCubit: driveDetailCubit,
        profileBloc: profileBloc,
      );
    });

    tearDown(() async {
      await db.close();
    });

    blocTest<FolderCreateCubit, FolderCreateState>(
      'does nothing when submitted without valid form',
      build: () => folderCreateCubit,
      act: (bloc) => bloc.submit(),
      expect: [],
    );
  });
}
