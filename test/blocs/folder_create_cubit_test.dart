import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:test/test.dart';

import '../mocks.dart';
import '../utils.dart';

void main() {
  group('FolderCreateCubit:', () {
    Database db;
    DriveDao driveDao;

    ArweaveService arweave;
    ProfileCubit profileCubit;
    FolderCreateCubit folderCreateCubit;

    setUp(() {
      db = getTestDb();
      driveDao = db.driveDao;

      arweave = ArweaveService(Arweave());
      profileCubit = MockProfileBloc();

      folderCreateCubit = FolderCreateCubit(
        arweave: arweave,
        driveDao: driveDao,
        profileCubit: profileCubit,
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
