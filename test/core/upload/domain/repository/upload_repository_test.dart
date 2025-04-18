import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/domain/repository/upload_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../test_utils/utils.dart';
import '../../../../utils/io_utils_test.dart';

class MockArDriveUploader extends Mock implements ArDriveUploader {}

class MockDriveDao extends Mock implements DriveDao {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockLicenseService extends Mock implements LicenseService {}

class MockDrive extends Mock implements Drive {}

class MockFolderEntry extends Mock implements FolderEntry {}

class MockUploadController extends Mock implements UploadController {}

void main() {
  group('UploadRepository', () {
    late UploadRepository uploadRepository;
    late MockArDriveUploader mockArDriveUploader;
    late MockDriveDao mockDriveDao;
    late MockArDriveAuth mockArDriveAuth;
    late MockLicenseService mockLicenseService;

    setUp(() {
      mockArDriveUploader = MockArDriveUploader();
      mockDriveDao = MockDriveDao();
      mockArDriveAuth = MockArDriveAuth();
      mockLicenseService = MockLicenseService();

      uploadRepository = UploadRepository(
        ardriveUploader: mockArDriveUploader,
        driveDao: mockDriveDao,
        auth: mockArDriveAuth,
        licenseService: mockLicenseService,
        ardriveIO: MockArDriveIO(),
      );

      registerFallbackValue(getTestWallet());
      registerFallbackValue(UploadType.d2n);
      registerFallbackValue(SecretKey([1, 2, 3, 4, 5]));
    });

    group('uploadFiles', () {
      test('should upload files successfully without names and license',
          () async {
        // Arrange
        final file = MockIOFile(contentType: 'text/plain');
        final metadataArgs = ARFSUploadMetadataArgs.file(
            driveId: 'drive-id',
            parentFolderId: 'folder-id',
            isPrivate: false,
            type: UploadType.d2n);

        final mockDrive = MockDrive();
        final mockFolderEntry = MockFolderEntry();
        final mockUploadController = MockUploadController();

        when(() => mockArDriveAuth.currentUser).thenReturn(getTestUser());

        when(() => mockDrive.privacy).thenReturn(DrivePrivacyTag.public);

        when(() => mockDrive.privacy).thenReturn('public');
        when(() => mockDrive.id).thenReturn('drive-id');
        when(() => mockFolderEntry.id).thenReturn('folder-id');
        when(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              driveKey: null,
              uploadThumbnail: false,
              type: UploadType.d2n,
            )).thenAnswer((_) async => mockUploadController);
        when(() => mockUploadController.onCompleteTask(any()))
            .thenAnswer((_) async => {});

        // Act
        final result = await uploadRepository.uploadFiles(
          files: [UploadFile(ioFile: file, parentFolderId: 'folder-id')],
          targetDrive: mockDrive,
          conflictingFiles: {},
          targetFolder: mockFolderEntry,
          uploadMethod: UploadMethod.ar,
          uploadThumbnail: false,
          assignedName: null,
          licenseStateConfigured: null,
        );

        // Assert
        expect(result, equals(mockUploadController));
        verify(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              driveKey: null,
              uploadThumbnail: false,
              type: UploadType.d2n,
            )).called(1);
      });

      test('should upload private files successfully without names and license',
          () async {
        // Arrange
        final file = await IOFile.fromData(Uint8List(0),
            name: 'dummy_file.txt', lastModifiedDate: DateTime.now());
        final metadataArgs = ARFSUploadMetadataArgs.file(
          driveId: 'drive-id',
          parentFolderId: 'folder-id',
          isPrivate: true,
          type: UploadType.d2n,
        );

        final mockDrive = MockDrive();
        final mockFolderEntry = MockFolderEntry();
        final mockUploadController = MockUploadController();

        when(() => mockArDriveAuth.currentUser).thenReturn(getTestUser());

        when(() => mockDrive.privacy).thenReturn(DrivePrivacyTag.public);

        /// PRIVATE DRIVE
        when(() => mockDrive.privacy).thenReturn('private');
        when(() => mockDrive.id).thenReturn('drive-id');
        when(() => mockFolderEntry.id).thenReturn('folder-id');
        when(() => mockDriveDao.getDriveKey(any(), any())).thenAnswer(
            (_) async => DriveKey(SecretKey([1, 2, 3, 4, 5]), true));
        when(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              driveKey: SecretKey([1, 2, 3, 4, 5]),
              uploadThumbnail: false,
              type: UploadType.d2n,
            )).thenAnswer((_) async => mockUploadController);
        when(() => mockUploadController.onCompleteTask(any()))
            .thenAnswer((_) async => {});

        // Act
        final result = await uploadRepository.uploadFiles(
          files: [UploadFile(ioFile: file, parentFolderId: 'folder-id')],
          targetDrive: mockDrive,
          conflictingFiles: {},
          targetFolder: mockFolderEntry,
          uploadMethod: UploadMethod.ar,
          uploadThumbnail: false,
          assignedName: null,
          licenseStateConfigured: null,
        );

        // Assert
        expect(result, equals(mockUploadController));
        verify(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              driveKey: SecretKey([1, 2, 3, 4, 5]),
              uploadThumbnail: false,
              type: UploadType.d2n,
            )).called(1);
      });

      test('should upload public files successfully with names and no license',
          () async {
        // Arrange
        final file = MockIOFile(contentType: 'text/plain');
        final metadataArgs = ARFSUploadMetadataArgs.file(
          driveId: 'drive-id',
          parentFolderId: 'folder-id',
          isPrivate: false,
          type: UploadType.d2n,
          assignedName: 'assigned-name',
        );

        final mockDrive = MockDrive();
        final mockFolderEntry = MockFolderEntry();
        final mockUploadController = MockUploadController();

        when(() => mockArDriveAuth.currentUser).thenReturn(getTestUser());

        when(() => mockDrive.privacy).thenReturn(DrivePrivacyTag.public);

        /// PUBLIC DRIVE
        when(() => mockDrive.privacy).thenReturn('public');
        when(() => mockDrive.id).thenReturn('drive-id');
        when(() => mockFolderEntry.id).thenReturn('folder-id');
        when(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              uploadThumbnail: false,
              type: UploadType.d2n,
            )).thenAnswer((_) async => mockUploadController);
        when(() => mockUploadController.onCompleteTask(any()))
            .thenAnswer((_) async => {});

        // Act
        final result = await uploadRepository.uploadFiles(
          files: [UploadFile(ioFile: file, parentFolderId: 'folder-id')],
          targetDrive: mockDrive,
          conflictingFiles: {},
          targetFolder: mockFolderEntry,
          uploadMethod: UploadMethod.ar,
          uploadThumbnail: false,
          assignedName: 'assigned-name',
          licenseStateConfigured: null,
        );

        // Assert
        expect(result, equals(mockUploadController));
        verify(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              uploadThumbnail: false,
              type: UploadType.d2n,
            )).called(1);
      });

      test('should upload private files successfully with names and no license',
          () async {
        // Arrange
        final file = MockIOFile(contentType: 'text/plain');
        final metadataArgs = ARFSUploadMetadataArgs.file(
          driveId: 'drive-id',
          parentFolderId: 'folder-id',
          isPrivate: true,
          type: UploadType.d2n,
          assignedName: 'assigned-name',
        );

        final mockDrive = MockDrive();
        final mockFolderEntry = MockFolderEntry();
        final mockUploadController = MockUploadController();

        when(() => mockArDriveAuth.currentUser).thenReturn(getTestUser());

        when(() => mockDrive.privacy).thenReturn(DrivePrivacyTag.public);

        /// PRIVATE DRIVE
        when(() => mockDrive.privacy).thenReturn('private');
        when(() => mockDrive.id).thenReturn('drive-id');
        when(() => mockFolderEntry.id).thenReturn('folder-id');
        when(() => mockDriveDao.getDriveKey(any(), any())).thenAnswer(
            (_) async => DriveKey(SecretKey([1, 2, 3, 4, 5]), true));
        when(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              uploadThumbnail: false,
              driveKey: SecretKey([1, 2, 3, 4, 5]),
              type: UploadType.d2n,
            )).thenAnswer((_) async => mockUploadController);
        when(() => mockUploadController.onCompleteTask(any()))
            .thenAnswer((_) async => {});

        // Act
        final result = await uploadRepository.uploadFiles(
          files: [UploadFile(ioFile: file, parentFolderId: 'folder-id')],
          targetDrive: mockDrive,
          conflictingFiles: {},
          targetFolder: mockFolderEntry,
          uploadMethod: UploadMethod.ar,
          uploadThumbnail: false,
          assignedName: 'assigned-name',
          licenseStateConfigured: null,
        );

        // Assert
        expect(result, equals(mockUploadController));
        verify(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              driveKey: SecretKey([1, 2, 3, 4, 5]),
              uploadThumbnail: false,
              type: UploadType.d2n,
            )).called(1);
      });

      test('should upload public files successfully with names and license',
          () async {
        final licenseState = LicenseState(
          meta: const LicenseMeta(
            licenseType: LicenseType.udl,
            licenseDefinitionTxId: 'license-definition-tx-id',
            name: 'license-name',
            shortName: 'license-short-name',
          ),
          params: UdlLicenseParams(
            commercialUse: UdlCommercialUse.allowed,
            derivations: UdlDerivation.unspecified,
            licenseFeeCurrency: UdlCurrency.ar,
            licenseFeeAmount: 100,
          ),
        );

        // Arrange
        final file = MockIOFile(contentType: 'text/plain');
        final metadataArgs = ARFSUploadMetadataArgs(
          driveId: 'drive-id',
          parentFolderId: 'folder-id',
          isPrivate: false,
          type: UploadType.d2n,
          assignedName: 'assigned-name',
          licenseAdditionalTags: licenseState.params?.toAdditionalTags(),
          licenseDefinitionTxId: 'license-definition-tx-id',
        );

        final mockDrive = MockDrive();
        final mockFolderEntry = MockFolderEntry();
        final mockUploadController = MockUploadController();

        when(() => mockArDriveAuth.currentUser).thenReturn(getTestUser());

        when(() => mockDrive.privacy).thenReturn(DrivePrivacyTag.public);

        /// PUBLIC DRIVE
        when(() => mockDrive.privacy).thenReturn('public');
        when(() => mockDrive.id).thenReturn('drive-id');
        when(() => mockFolderEntry.id).thenReturn('folder-id');
        when(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              uploadThumbnail: false,
              type: UploadType.d2n,
            )).thenAnswer((_) async => mockUploadController);
        when(() => mockUploadController.onCompleteTask(any()))
            .thenAnswer((_) async => {});

        // Act
        final result = await uploadRepository.uploadFiles(
          files: [UploadFile(ioFile: file, parentFolderId: 'folder-id')],
          targetDrive: mockDrive,
          conflictingFiles: {},
          targetFolder: mockFolderEntry,
          uploadMethod: UploadMethod.ar,
          uploadThumbnail: false,
          assignedName: 'assigned-name',
          licenseStateConfigured: licenseState,
        );

        // Assert
        expect(result, equals(mockUploadController));
        // here we ensure that the license tags are added to the metadata args
        verify(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              uploadThumbnail: false,
              type: UploadType.d2n,
            )).called(1);
      });

      test('should upload private files successfully with names and license',
          () async {
        final licenseState = LicenseState(
          meta: const LicenseMeta(
            licenseType: LicenseType.udl,
            licenseDefinitionTxId: 'license-definition-tx-id',
            name: 'license-name',
            shortName: 'license-short-name',
          ),
          params: UdlLicenseParams(
            commercialUse: UdlCommercialUse.allowed,
            derivations: UdlDerivation.unspecified,
            licenseFeeCurrency: UdlCurrency.ar,
            licenseFeeAmount: 100,
          ),
        );

        // Arrange
        final file = MockIOFile(contentType: 'text/plain');
        final metadataArgs = ARFSUploadMetadataArgs(
          driveId: 'drive-id',
          parentFolderId: 'folder-id',
          isPrivate: true,
          type: UploadType.d2n,
          assignedName: 'assigned-name',
          licenseAdditionalTags: licenseState.params?.toAdditionalTags(),
          licenseDefinitionTxId: 'license-definition-tx-id',
        );

        final mockDrive = MockDrive();
        final mockFolderEntry = MockFolderEntry();
        final mockUploadController = MockUploadController();

        when(() => mockArDriveAuth.currentUser).thenReturn(getTestUser());

        when(() => mockDrive.privacy).thenReturn(DrivePrivacyTag.public);

        /// PUBLIC DRIVE
        when(() => mockDrive.privacy).thenReturn('private');
        when(() => mockDrive.id).thenReturn('drive-id');
        when(() => mockFolderEntry.id).thenReturn('folder-id');
        when(() => mockDriveDao.getDriveKey(any(), any())).thenAnswer(
            (_) async => DriveKey(SecretKey([1, 2, 3, 4, 5]), true));
        when(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              uploadThumbnail: false,
              type: UploadType.d2n,
              driveKey: SecretKey([1, 2, 3, 4, 5]),
            )).thenAnswer((_) async => mockUploadController);
        when(() => mockUploadController.onCompleteTask(any()))
            .thenAnswer((_) async => {});

        // Act
        final result = await uploadRepository.uploadFiles(
          files: [UploadFile(ioFile: file, parentFolderId: 'folder-id')],
          targetDrive: mockDrive,
          conflictingFiles: {},
          targetFolder: mockFolderEntry,
          uploadMethod: UploadMethod.ar,
          uploadThumbnail: false,
          assignedName: 'assigned-name',
          licenseStateConfigured: licenseState,
        );

        // Assert
        expect(result, equals(mockUploadController));
        // here we ensure that the license tags are added to the metadata args
        verify(() => mockArDriveUploader.uploadFiles(
              files: [(metadataArgs, file)],
              wallet: any(named: 'wallet'),
              driveKey: SecretKey([1, 2, 3, 4, 5]),
              uploadThumbnail: false,
              type: UploadType.d2n,
            )).called(1);
      });
    });
  });
}

class MockIOFile extends IOFile with EquatableMixin {
  MockIOFile({required super.contentType});

  @override
  DateTime get lastModifiedDate => DateTime(2010, 1, 1);

  @override
  FutureOr<int> get length => 1;

  @override
  String get name => 'dummy_file.txt';
  @override
  Stream<Uint8List> openReadStream([int start = 0, int? end]) async* {
    yield Uint8List(0);
  }

  @override
  String get path => 'path';

  @override
  Future<Uint8List> readAsBytes() async => Uint8List(0);

  @override
  Future<String> readAsString() async => 'dummy_file.txt';

  @override
  List<Object?> get props => [
        name,
        lastModifiedDate,
        contentType,
      ];
}
