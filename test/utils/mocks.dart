import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/profileTypes.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:mocktail/mocktail.dart';

class MockArweave extends Mock implements Arweave {}

class MockConfig extends Mock implements AppConfig {}

class MockContext extends Mock implements BuildContext {}

class MockArweaveService extends Mock implements ArweaveService {}

class MockProfileDao extends Mock implements ProfileDao {}

class MockDriveDao extends Mock implements DriveDao {}

class MockSyncBloc extends MockCubit<SyncState> implements SyncCubit {}

class MockDrivesCubit extends MockCubit<DrivesState> implements DrivesCubit {}

class MockDriveDetailCubit extends MockCubit<DriveDetailState>
    implements DriveDetailCubit {}

class MockProfileCubit extends MockCubit<ProfileState> implements ProfileCubit {
}

class MockUploadBloc extends MockCubit<UploadState> implements UploadCubit {}

class MockProfileLoadDetails extends Mock implements ProfileLoadDetails {}

class MockProfile extends Mock implements Profile {
  @override
  int get profileType => ProfileType.JSON.index;
  @override
  String get id => 'testID';
  @override
  String get username => 'testUserName';
}
