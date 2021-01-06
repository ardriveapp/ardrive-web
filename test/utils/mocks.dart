import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mockito/mockito.dart';

class MockArweave extends Mock implements Arweave {}

class MockArweaveService extends Mock implements ArweaveService {}

class MockProfileDao extends Mock implements ProfileDao {}

class MockDriveDao extends Mock implements DriveDao {}

class MockSyncBloc extends MockBloc<SyncState> implements SyncCubit {}

class MockDrivesCubit extends MockBloc<DrivesState> implements DrivesCubit {}

class MockDriveDetailCubit extends MockBloc<DrivesState>
    implements DriveDetailCubit {}

class MockProfileCubit extends MockBloc<ProfileState> implements ProfileCubit {}

class MockUploadBloc extends MockBloc<UploadState> implements UploadCubit {}
