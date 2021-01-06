import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:test/test.dart';

import '../utils/utils.dart';

void main() {
  group('DrivesCubit', () {
    Database db;
    DriveDao driveDao;

    ProfileCubit profileCubit;
    DrivesCubit drivesCubit;

    setUp(() {
      db = getTestDb();
      driveDao = db.driveDao;

      profileCubit = MockProfileCubit();

      drivesCubit = DrivesCubit(
        profileCubit: profileCubit,
        driveDao: driveDao,
      );
    });

    tearDown(() async {
      await db.close();
    });

    blocTest<DrivesCubit, DrivesState>(
      'create public drive',
      build: () => drivesCubit,
      act: (bloc) async {},
      expect: [
        DrivesLoadInProgress(),
        DrivesLoadSuccess(),
      ],
    );
  });
}
