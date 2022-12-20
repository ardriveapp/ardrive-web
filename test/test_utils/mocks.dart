import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/decrypt.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:mocktail/mocktail.dart';

class MockArweave extends Mock implements Arweave {}

class MockConfig extends Mock implements AppConfig {}

class MockContext extends Mock implements BuildContext {}

class MockArweaveService extends Mock implements ArweaveService {}

class MockTurboService extends Mock implements TurboService {}

class MockProfileDao extends Mock implements ProfileDao {}

class MockDriveDao extends Mock implements DriveDao {}

class MockSyncBloc extends MockCubit<SyncState> implements SyncCubit {}

class MockDrivesCubit extends MockCubit<DrivesState> implements DrivesCubit {}

class MockDriveDetailCubit extends MockCubit<DriveDetailState>
    implements DriveDetailCubit {}

class MockProfileCubit extends MockCubit<ProfileState> implements ProfileCubit {
}

class MockUploadBloc extends MockCubit<UploadState> implements UploadCubit {}

class MockPstService extends Mock implements PstService {}

class MockUploadPlanUtils extends Mock implements UploadPlanUtils {}

class MockBiometricAuthentication extends Mock
    implements BiometricAuthentication {}

class MockArDriveDownloader extends Mock implements ArDriveDownloader {}

class MockDownloadService extends Mock implements DownloadService {}

class MockDecrypt extends Mock implements Decrypt {}

class MockARFSRepository extends Mock implements ARFSRepository {}

class MockAppFlavors extends Mock implements AppFlavors {}
