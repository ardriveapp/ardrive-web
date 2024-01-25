@Tags(['broken'])

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/fakes.dart';
import '../test_utils/utils.dart';

class MockActivityTracker extends Mock implements ActivityTracker {}

void main() {
  group('DrivesCubit', () {
    late Database db;
    late DriveDao driveDao;

    late ProfileCubit profileCubit;
    late DrivesCubit drivesCubit;
    late PromptToSnapshotBloc promptToSnapshotBloc;

    setUp(() {
      registerFallbackValue(SyncStateFake());
      registerFallbackValue(ProfileStateFake());
      db = getTestDb();
      driveDao = db.driveDao;

      profileCubit = MockProfileCubit();
      promptToSnapshotBloc = MockPromptToSnapshotBloc();

      drivesCubit = DrivesCubit(
        activityTracker: MockActivityTracker(),
        auth: MockArDriveAuth(),
        profileCubit: profileCubit,
        driveDao: driveDao,
        promptToSnapshotBloc: promptToSnapshotBloc,
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
