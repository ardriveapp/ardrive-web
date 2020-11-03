import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:test/test.dart';

import '../utils/utils.dart';

void main() {
  group('DrivesCubit', () {
    Database db;
    DrivesDao drivesDao;

    ProfileCubit profileCubit;
    DrivesCubit drivesCubit;

    setUp(() {
      db = getTestDb();
      drivesDao = db.drivesDao;

      profileCubit = MockProfileCubit();

      drivesCubit = DrivesCubit(
        profileCubit: profileCubit,
        drivesDao: drivesDao,
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
