import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';
import '../test_utils/utils.dart';

void main() {
  group('DrivesCubit', () {
    late Database db;
    late DriveDao driveDao;

    late ProfileCubit profileCubit;
    late DrivesCubit drivesCubit;

    setUp(() {
      registerFallbackValue(SyncStateFake());
      registerFallbackValue(ProfileStateFake());
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
      expect: () => [
        DrivesLoadInProgress(),
      ],
    );
  });
}
