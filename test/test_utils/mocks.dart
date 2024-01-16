import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/config/config_fetcher.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/utils/app_flavors.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
// ignore: depend_on_referenced_packages
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pst/pst.dart';

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

class MockProfileCubit extends MockCubit<ProfileState>
    implements ProfileCubit {}

class MockUploadBloc extends MockCubit<UploadState> implements UploadCubit {}

class MockPstService extends Mock implements PstService {}

class MockUploadPlanUtils extends Mock implements UploadPlanUtils {}

class MockBiometricAuthentication extends Mock
    implements BiometricAuthentication {}

class MockArDriveDownloader extends Mock implements ArDriveMobileDownloader {}

class MockDownloadService extends Mock implements DownloadService {}

class MockArDriveCrypto extends Mock implements ArDriveCrypto {}

class MockARFSRepository extends Mock implements ARFSRepository {}

class MockAppFlavors extends Mock implements AppFlavors {}

class MockUserRepository extends Mock implements UserRepository {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockArConnectService extends Mock implements ArConnectService {}

class MockTabVisibilitySingleton extends Mock
    implements TabVisibilitySingleton {}

class MockUploadFileSizeChecker extends Mock implements UploadFileSizeChecker {}

class MockSecureKeyValueStore extends Mock implements SecureKeyValueStore {}

class MockDatabaseHelpers extends Mock implements DatabaseHelpers {}

class MockConfigFetcher extends Mock implements ConfigFetcher {}

class MockConfigService extends Mock implements ConfigService {}

class MockEnvFetcher extends Mock implements EnvFetcher {}

class MockTransactionCommonMixin extends Mock
    implements TransactionCommonMixin {}

class MockDeviceInfoPlugin extends Mock implements DeviceInfoPlugin {}

class MockARFSFile extends ARFSFileEntity {
  MockARFSFile({
    required super.appName,
    required super.appVersion,
    required super.arFS,
    required super.driveId,
    required super.entityType,
    required super.name,
    required super.txId,
    required super.unixTime,
    required super.id,
    required super.size,
    required super.lastModifiedDate,
    required super.parentFolderId,
    super.contentType,
  });
}

class MockARFSDrive extends ARFSDriveEntity {
  MockARFSDrive({
    required super.appName,
    required super.appVersion,
    required super.arFS,
    required super.driveId,
    required super.entityType,
    required super.name,
    required super.txId,
    required super.unixTime,
    required super.drivePrivacy,
    required super.rootFolderId,
  });
}

MockARFSFile createMockFile(
    {appName = 'appName',
    appVersion = 'appVersion',
    arFS = 'arFS',
    driveId = 'driveId',
    entityType = EntityType.file,
    txId = 'txId',
    unixTime,
    id = 'id',
    lastModifiedDate,
    parentFolderId = 'parentFolderId',
    size = 100,
    name = 'name'}) {
  return MockARFSFile(
    appName: appName,
    appVersion: appVersion,
    arFS: arFS,
    driveId: driveId,
    entityType: entityType,
    name: name,
    txId: txId,
    unixTime: unixTime ?? DateTime.now(),
    id: id,
    size: size,
    lastModifiedDate: lastModifiedDate ?? DateTime.now(),
    parentFolderId: parentFolderId,
  );
}

MockARFSDrive createMockDrive(
    {appName = 'appName',
    appVersion = 'appVersion',
    arFS = 'arFS',
    driveId = 'driveId',
    entityType = EntityType.drive,
    txId = 'txId',
    unixTime,
    drivePrivacy = DrivePrivacy.private,
    rootFolderId = 'rootFolderId',
    name = 'name'}) {
  return MockARFSDrive(
      appName: appName,
      appVersion: appVersion,
      arFS: arFS,
      driveId: driveId,
      entityType: entityType,
      name: name,
      txId: txId,
      unixTime: unixTime ?? DateTime.now(),
      drivePrivacy: drivePrivacy,
      rootFolderId: rootFolderId);
}

FileDataTableItem createMockFileDataTableItem(
    {appName = 'appName',
    appVersion = 'appVersion',
    arFS = 'arFS',
    driveId = 'driveId',
    dataTxId = 'txId',
    NetworkTransaction? dataTx,
    NetworkTransaction? metadataTx,
    unixTime,
    fileId = 'id',
    lastModifiedDate,
    lastUpdated,
    DateTime? dateCreated,
    pinnedDataOwnerAddress,
    parentFolderId = 'parentFolderId',
    size = 100,
    name = 'name',
    path = 'path',
    index = 0,
    isOwner = true}) {
  return FileDataTableItem(
      fileId: fileId,
      driveId: driveId,
      parentFolderId: parentFolderId,
      dataTxId: dataTxId,
      lastUpdated: lastUpdated ?? DateTime.now(),
      lastModifiedDate: lastModifiedDate ?? DateTime.now(),
      metadataTx: metadataTx,
      dataTx: dataTx,
      name: name,
      size: size,
      dateCreated: dateCreated ?? DateTime.now(),
      contentType: 'contentType',
      path: path,
      index: index,
      pinnedDataOwnerAddress: pinnedDataOwnerAddress,
      isOwner: isOwner);
}

FolderDataTableItem createMockFolderDataTableItem(
    {appVersion = 'appVersion',
    arFS = 'arFS',
    driveId = 'driveId',
    folderId = 'folderId',
    contentType = 'contentType',
    lastModifiedDate,
    lastUpdated,
    DateTime? dateCreated,
    isGhostFolder = false,
    parentFolderId = '',
    name = 'name',
    path = 'path',
    fileStatusFromTransactions,
    index = 0,
    isOwner = true}) {
  return FolderDataTableItem(
      driveId: driveId,
      folderId: folderId,
      name: name,
      lastUpdated: lastUpdated ?? DateTime.now(),
      dateCreated: dateCreated ?? DateTime.now(),
      contentType: contentType,
      path: path,
      fileStatusFromTransactions: fileStatusFromTransactions,
      parentFolderId: parentFolderId,
      isGhostFolder: isGhostFolder,
      index: index,
      isOwner: isOwner);
}

DriveDataItem createMockDriveDataItem(
    {id = 'id',
    driveId = 'driveId',
    name = 'name',
    lastUpdated,
    dateCreated,
    index = 0,
    isOwner = true}) {
  return DriveDataItem(
      id: id,
      driveId: driveId,
      name: name,
      lastUpdated: lastUpdated ?? DateTime.now(),
      dateCreated: dateCreated ?? DateTime.now(),
      index: index,
      isOwner: isOwner);
}

FolderEntry createMockFolderEntry(
    {name = 'name',
    id = 'id',
    driveId = 'driveId',
    path = 'name',
    contentType = 'contentType',
    lastUpdated,
    dateCreated,
    parentFolderId,
    isGhost = false,
    index = 0,
    isOwner = true}) {
  return FolderEntry(
    name: name,
    id: id,
    driveId: driveId,
    lastUpdated: DateTime.now(),
    dateCreated: DateTime.now(),
    path: path,
    parentFolderId: parentFolderId,
    isGhost: isGhost,
  );
}

FileEntry createMockFileEntry(
    {name = 'name',
    id = 'id',
    driveId = 'driveId',
    path = 'name',
    dataTxId = 'txId',
    contentType = 'contentType',
    dataContentType,
    size = 100,
    lastModifiedDate,
    dateCreated,
    lastUpdated,
    parentFolderId = 'parentFolderId',
    bundledIn,
    isGhost = false,
    index = 0,
    isOwner = true}) {
  return FileEntry(
    name: name,
    id: id,
    driveId: driveId,
    dataTxId: dataTxId,
    dataContentType: dataContentType,
    size: size,
    lastModifiedDate: lastModifiedDate ?? DateTime.now(),
    dateCreated: dateCreated ?? DateTime.now(),
    lastUpdated: lastUpdated ?? DateTime.now(),
    path: path,
    parentFolderId: parentFolderId,
    bundledIn: bundledIn,
  );
}
