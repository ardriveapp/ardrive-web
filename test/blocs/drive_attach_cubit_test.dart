import 'package:bloc_test/bloc_test.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('DriveAttachCubit', () {
    ArweaveService arweave;
    DrivesDao drivesDao;
    ProfileBloc profileBloc;
    SyncBloc syncBloc;
    DrivesBloc drivesBloc;
    DriveAttachCubit driveAttachCubit;

    setUp(() {
      arweave = MockArweave();
      drivesDao = MockDrivesDao();
      syncBloc = MockSyncBloc();
      drivesBloc = MockDrivesBloc();
      profileBloc = MockProfileBloc();

      profileBloc.emit(ProfileLoaded());

      driveAttachCubit = DriveAttachCubit(
        arweave: arweave,
        drivesDao: drivesDao,
        syncBloc: syncBloc,
        drivesBloc: drivesBloc,
        profileBloc: profileBloc,
      );
    });

    blocTest<DriveAttachCubit, DriveAttachState>(
      'does nothing when submitted without valid form',
      build: () => driveAttachCubit,
      act: (bloc) => bloc.submit(),
      expect: [],
      verify: (_) {
        verifyZeroInteractions(arweave);
        verifyZeroInteractions(drivesDao);
        verifyZeroInteractions(syncBloc);
        verifyZeroInteractions(drivesBloc);
        verifyZeroInteractions(profileBloc);
      },
    );
  });
}
