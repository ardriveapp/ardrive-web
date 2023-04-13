import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/decrypt.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/crypto/authenticate.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/html/html_util.dart';
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

class MockProfileDao extends Mock implements ProfileDao {}

class MockDriveDao extends Mock implements DriveDao {}

class MockArDriveIO extends Mock implements ArDriveIO {}

class MockIOFileAdapter extends Mock implements IOFileAdapter {}

class MockAuthenticate extends Mock implements Authenticate {}

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

class MockTabVisibilitySingleton extends Mock
    implements TabVisibilitySingleton {}

class MockUploadFileChecker extends Mock implements UploadFileChecker {}

class MockIOFile extends IOFile {
  final DateTime _lastModifiedDate;
  final String _name;
  final String _path;
  final Uint8List _data;

  MockIOFile({
    required super.contentType,
    required DateTime lastModifiedDate,
    required String name,
    required String path,
    required Uint8List data,
  }) : _lastModifiedDate = lastModifiedDate,
       _name = name,
       _path = path,
       _data = data;

  @override
  DateTime get lastModifiedDate => _lastModifiedDate;

  @override
  int get length => _data.length;
  
  @override
  String get name => _name;

  @override
  String get path => _path;

  @override
  Stream<Uint8List> openReadStream([int start = 0, int? end]) => Stream.value(_data);

  @override
  Future<Uint8List> readAsBytes() => Future.value(_data);

  @override
  Future<String> readAsString() async => Future.value(String.fromCharCodes(_data));
}