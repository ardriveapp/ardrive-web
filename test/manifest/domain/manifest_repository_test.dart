import 'dart:typed_data';

import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/core/arfs/utils/arfs_revision_status_utils.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/manifest_data.dart';
import 'package:ardrive/manifest/domain/exceptions.dart';
import 'package:ardrive/manifest/domain/manifest_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

class MockARFSFileUploadMetadata extends Mock
    implements ARFSFileUploadMetadata {}

class MockManifestUploadParams extends Mock implements ManifestUploadParams {}

class MockUploadController extends Mock implements UploadController {}

class MockFolderNode extends Mock implements FolderNode {}

class MockFolderEntry extends Mock implements FolderEntry {}

class MockFileEntry extends Mock implements FileEntry {}

class MockManifestDataBuilder extends Mock implements ManifestDataBuilder {}

class MockARFSVersionRevisionStatusUtils extends Mock
    implements ARFSRevisionStatusUtils {}

void main() async {
  group(
    'ManifestRepositoryImpl',
    () {
      late ManifestRepositoryImpl repository;
      late MockDriveDao mockDriveDao;
      late MockArDriveUploader mockUploader;
      late ARFSFileUploadMetadata mockMetadata;
      late ManifestUploadParams mockUploadParams;
      late MockFolderRepository mockFolderRepository;
      late MockUploadController mockUploadController;
      late MockFolderEntry mockParentFolder;
      late IOFile mockManifestFile;
      late MockManifestDataBuilder mockBuilder;
      late ARFSRevisionStatusUtils mockVersionRevisionStatusUtils;
      late MockArnsRepository mockArnsRepository;
      late MockFileRepository mockFileRepository;
      setUp(() {
        mockDriveDao = MockDriveDao();
        mockMetadata = MockARFSFileUploadMetadata();
        mockUploadParams = MockManifestUploadParams();
        mockUploader = MockArDriveUploader();
        mockFolderRepository = MockFolderRepository();
        mockBuilder = MockManifestDataBuilder();
        mockVersionRevisionStatusUtils = MockARFSVersionRevisionStatusUtils();
        mockArnsRepository = MockArnsRepository();
        mockFileRepository = MockFileRepository();
        registerFallbackValue(FileEntity());
        registerFallbackValue(const FileRevisionsCompanion());
        registerFallbackValue(
          ARNSUndernameFactory.create(
            name: 'undername',
            domain: 'domain',
            transactionId: 'transaction_id',
          ),
        );

        repository = ManifestRepositoryImpl(
          mockDriveDao,
          mockUploader,
          mockFolderRepository,
          mockBuilder,
          mockVersionRevisionStatusUtils,
          mockArnsRepository,
          mockFileRepository,
        );

        // Setup mock data and behavior
        when(() => mockMetadata.size).thenReturn(1024);
        when(() => mockMetadata.parentFolderId).thenReturn('folder123');
        when(() => mockMetadata.name).thenReturn('TestManifest');
        when(() => mockMetadata.id).thenReturn('id123');
        when(() => mockMetadata.driveId).thenReturn('drive123');
        when(() => mockMetadata.dataTxId).thenReturn('dataTx123');
        when(() => mockMetadata.metadataTxId).thenReturn('metadataTx123');
        when(() => mockMetadata.lastModifiedDate).thenReturn(DateTime.now());

        when(() => mockUploadParams.driveId).thenReturn('drive123');
        when(() => mockUploadParams.parentFolderId).thenReturn('folder123');
        when(() => mockUploadParams.wallet).thenReturn(Wallet());
      });

      group('saveManifestOnDatabase', () {
        test('Successfully saves a new manifest', () async {
          when(() => mockFileRepository.updateFile<FileEntity>(any()))
              .thenAnswer((_) async => []);
          when(() => mockFileRepository.updateFileRevision(
              any(), RevisionAction.create)).thenAnswer((_) async => []);

          await repository.saveManifestOnDatabase(manifest: mockMetadata);

          verify(() => mockFileRepository.updateFile<FileEntity>(any()))
              .called(1);
          verify(() => mockFileRepository.updateFileRevision(
              any(), RevisionAction.create)).called(1);
        });

        test('Exception when saving manifest on database', () async {
          mockManifestFile = await IOFileAdapter().fromData(Uint8List(1024),
              name: 'TestManifest', lastModifiedDate: DateTime.now());
          when(() => mockUploadParams.manifestFile)
              .thenReturn(mockManifestFile);

          when(() => mockDriveDao.transaction(any()))
              .thenThrow(Exception('DB Error'));

          expect(
            repository.saveManifestOnDatabase(manifest: mockMetadata),
            throwsA(isA<ManifestCreationException>()),
          );
        });
      });

      group('uploadManifest', () {
        late FileUploadTask uploadTaskTurbo;
        late ARFSUploadMetadataArgs argsTurbo;
        setUp(() async {
          mockManifestFile = await IOFileAdapter().fromData(Uint8List(1024),
              name: 'TestManifest', lastModifiedDate: DateTime.now());

          registerFallbackValue(FileEntity());
          registerFallbackValue(const FileRevisionsCompanion());
          registerFallbackValue(UploadType.turbo);
          registerFallbackValue(Wallet());
          registerFallbackValue(mockManifestFile);

          argsTurbo = ARFSUploadMetadataArgs(
            driveId: 'drive123',
            parentFolderId: 'folder123',
            entityId: null,
            isPrivate: false,
            type: UploadType.turbo,
            privacy: DrivePrivacyTag.public,
          );

          when(() => mockUploadParams.manifestFile)
              .thenReturn(mockManifestFile);

          registerFallbackValue(argsTurbo);

          when(() => mockUploadParams.manifestFile)
              .thenReturn(mockManifestFile);

          mockUploadController = MockUploadController();

          uploadTaskTurbo = FileUploadTask(
            content: [mockMetadata],
            file: mockManifestFile,
            metadata: mockMetadata,
            type: UploadType.turbo,
            uploadThumbnail: true,
          );

          when(() => mockUploader.upload(
                file: mockManifestFile,
                args: any(named: 'args'),
                wallet: any(named: 'wallet'),
                type: any(named: 'type'),
              )).thenAnswer((_) async {
            when(() => mockUploadController.onDone(any()))
                .thenAnswer((invocation) {
              final onDone = invocation.positionalArguments.first as Function;
              onDone([uploadTaskTurbo]);
            });
            when(() => mockUploadController.onError(any())).thenReturn(null);
            return mockUploadController;
          });

          // Ensure transaction method is correctly mocked to return a Future
          when(() => mockDriveDao.runTransaction(any()))
              .thenAnswer((invocation) async {
            final Function transaction = invocation.positionalArguments[0];
            await transaction();
          });

          when(() => mockDriveDao.writeFileEntity(any()))
              .thenAnswer((_) async {});
          when(() => mockDriveDao.insertFileRevision(any()))
              .thenAnswer((_) async {});
        });

        test('Successfully uploads and saves manifest USING TURBO', () async {
          // TURBO
          when(() => mockUploadParams.uploadType).thenReturn(UploadType.turbo);
          when(() => mockFileRepository.updateFile<FileEntity>(any()))
              .thenAnswer((_) async => []);
          when(() => mockFileRepository.updateFileRevision(
              any(), RevisionAction.create)).thenAnswer((_) async => []);

          await repository.uploadManifest(params: mockUploadParams);
          // Verify interactions
          verify(() => mockUploader.upload(
                file: mockManifestFile,
                args: any(named: 'args'),
                wallet: any(named: 'wallet'),

                /// TURBO
                type: UploadType.turbo,
              )).called(1);

          verify(() => mockFileRepository.updateFile<FileEntity>(any()))
              .called(1);
          verify(() => mockFileRepository.updateFileRevision(
              any(), RevisionAction.create)).called(1);
        });

        test(
            'Successfully uploads and saves manifest USING TURBO and existing manifest',
            () async {
          // TURBO
          when(() => mockUploadParams.uploadType).thenReturn(UploadType.turbo);
          when(() => mockUploadParams.existingManifestFileId)
              .thenReturn('existingManifestFileId');
          when(() => mockFileRepository.updateFile<FileEntity>(any()))
              .thenAnswer((_) async => []);
          when(() => mockFileRepository.updateFileRevision(
                  any(), RevisionAction.uploadNewVersion))
              .thenAnswer((_) async => []);

          await repository.uploadManifest(params: mockUploadParams);
          // Verify interactions
          verify(() => mockUploader.upload(
                file: mockManifestFile,
                args: any(named: 'args'),
                wallet: any(named: 'wallet'),

                /// TURBO
                type: UploadType.turbo,
              )).called(1);

          verify(() => mockFileRepository.updateFile<FileEntity>(any()))
              .called(1);
          verify(() => mockFileRepository.updateFileRevision(
              any(), RevisionAction.uploadNewVersion)).called(1);
        });

        test(
            'Successfully uploads and saves manifest using Turbo and Saving a new ARNS record if undername is provided',
            () async {
          // TURBO
          when(() => mockUploadParams.uploadType).thenReturn(UploadType.turbo);

          when(() => mockUploadController.onDone(any()))
              .thenAnswer((invocation) {
            final onDone = invocation.positionalArguments.first as Function;
            onDone([uploadTaskTurbo]);
          });

          when(() => mockFileRepository.updateFile<FileEntity>(any()))
              .thenAnswer((_) async => []);
          when(() => mockFileRepository.updateFileRevision(
              any(), RevisionAction.create)).thenAnswer((_) async => []);

          when(() => mockArnsRepository.setUndernamesToFile(
                undername: any(named: 'undername'),
                fileId: any(named: 'fileId'),
                uploadNewRevision: any(named: 'uploadNewRevision'),
                driveId: any(named: 'driveId'),
                processId: any(named: 'processId'),
              )).thenAnswer((_) async {
            // success
          });

          await repository.uploadManifest(
            params: mockUploadParams,
            processId: 'process_id',
            undername: ARNSUndernameFactory.create(
              name: 'undername',
              domain: 'domain',
              transactionId: 'transaction_id',
            ),
          );
          // Verify interactions
          verify(() => mockUploader.upload(
                file: mockManifestFile,
                args: any(named: 'args'),
                wallet: any(named: 'wallet'),

                /// TURBO
                type: UploadType.turbo,
              )).called(1);

          verify(() => mockArnsRepository.setUndernamesToFile(
                undername: any(named: 'undername'),
                fileId: any(named: 'fileId'),
                uploadNewRevision: any(named: 'uploadNewRevision'),
                driveId: any(named: 'driveId'),
                processId: any(named: 'processId'),
              )).called(1);

          verify(() => mockFileRepository.updateFile<FileEntity>(any()))
              .called(1);
          verify(() => mockFileRepository.updateFileRevision(
              any(), RevisionAction.create)).called(1);
        });

        test(
            'Successfully uploads and saves manifest using Ar and Saving a new ARNS record if undername is provided',
            () async {
          // TURBO
          when(() => mockUploadParams.uploadType).thenReturn(UploadType.d2n);

          when(() => mockUploadController.onDone(any()))
              .thenAnswer((invocation) {
            final onDone = invocation.positionalArguments.first as Function;
            onDone([uploadTaskTurbo]);
          });

          when(() => mockFileRepository.updateFile<FileEntity>(any()))
              .thenAnswer((_) async => []);
          when(() => mockFileRepository.updateFileRevision(
              any(), RevisionAction.create)).thenAnswer((_) async => []);

          when(() => mockArnsRepository.setUndernamesToFile(
                undername: any(named: 'undername'),
                fileId: any(named: 'fileId'),
                uploadNewRevision: any(named: 'uploadNewRevision'),
                driveId: any(named: 'driveId'),
                processId: any(named: 'processId'),
              )).thenAnswer((_) async {
            // success
          });

          await repository.uploadManifest(
            params: mockUploadParams,
            processId: 'process_id',
            undername: ARNSUndernameFactory.create(
              name: 'undername',
              domain: 'domain',
              transactionId: 'transaction_id',
            ),
          );
          // Verify interactions
          verify(() => mockUploader.upload(
                file: mockManifestFile,
                args: any(named: 'args'),
                wallet: any(named: 'wallet'),

                /// Uploads using AR
                type: UploadType.d2n,
              )).called(1);

          verify(() => mockArnsRepository.setUndernamesToFile(
                undername: any(named: 'undername'),
                fileId: any(named: 'fileId'),
                uploadNewRevision: any(named: 'uploadNewRevision'),
                driveId: any(named: 'driveId'),
                processId: any(named: 'processId'),
              )).called(1);
        });

        test('Handles upload failure', () async {
          when(() => mockUploader.upload(
                file: any(named: 'file'),
                args: any(named: 'args'),
                wallet: any(named: 'wallet'),
                type: any(named: 'type'),
              )).thenThrow(Exception('Upload failed'));

          expect(() => repository.uploadManifest(params: mockUploadParams),
              throwsA(isA<ManifestCreationException>()));
        });
      });

      group('hasPendingFilesOnTargetFolder', () {
        setUp(() {
          registerFallbackValue(MockFolderNode());
        });

        test('Returns false when no pending files are found', () async {
          when(() =>
                  mockVersionRevisionStatusUtils.hasPendingFilesOnTargetFolder(
                      folderNode: any(named: 'folderNode')))
              .thenAnswer((_) async => false);

          final result = await repository.hasPendingFilesOnTargetFolder(
            folderNode: MockFolderNode(),
          );

          expect(result, false);
        });

        test('Returns true when pending files are found', () async {
          when(() =>
                  mockVersionRevisionStatusUtils.hasPendingFilesOnTargetFolder(
                      folderNode: any(named: 'folderNode')))
              .thenAnswer((_) async => true);

          final result = await repository.hasPendingFilesOnTargetFolder(
            folderNode: MockFolderNode(),
          );

          expect(result, true);
        });
      });

      // needed since the lastModifiedDate is set to DateTime.now()
      group('getManifestFile', () {
        registerFallbackValue(Uint8List(1024));
        late MockFolderNode mockRootFolderNode;
        late MockFolderNode folderNode;
        late ManifestData stubManifestData;

        setUp(() {
          mockRootFolderNode = MockFolderNode();
          folderNode = MockFolderNode();
          stubManifestData = ManifestData(ManifestIndex('index.html'),
              {'path/to/file': ManifestPath('dataTxId', fileId: 'fileId')});

          registerFallbackValue(mockRootFolderNode);

          mockParentFolder = MockFolderEntry();
          when(() => mockParentFolder.id).thenReturn('parentFolderId');
          when(() => mockRootFolderNode.searchForFolder(any()))
              .thenReturn(folderNode);
          when(() => mockDriveDao.getFolderTree(any(), any()))
              .thenAnswer((_) async => folderNode);
          when(() => mockBuilder.build(folderNode: folderNode))
              .thenAnswer((_) async => stubManifestData);
        });

        test('Successfully retrieves and constructs a manifest file', () async {
          final result = await repository.getManifestFile(
              parentFolder: mockParentFolder,
              manifestName: 'manifest.json',
              rootFolderNode: mockRootFolderNode,
              driveId: 'drive123');

          expect(result, isA<IOFile>());
          verify(() => mockBuilder.build(folderNode: folderNode)).called(1);
        });

        test('Handles error when building manifest data', () async {
          when(() => mockBuilder.build(folderNode: any(named: 'folderNode')))
              .thenThrow(
            Exception('Failed to build manifest data'),
          );

          expect(
            () => repository.getManifestFile(
              parentFolder: mockParentFolder,
              manifestName: 'manifest.json',
              rootFolderNode: mockRootFolderNode,
              driveId: 'drive123',
            ),
            throwsA(isA<ManifestCreationException>()),
          );
        });
      });

      group('checkNameConflictAndReturnExistingFileId', () {
        late MockFolderEntry mockFolderEntry;
        late MockFileEntry mockFileEntry;

        setUp(() {
          mockFolderEntry = MockFolderEntry();
          mockFileEntry = MockFileEntry();
          when(() => mockFolderRepository.existingFoldersWithName(
                  driveId: any(named: 'driveId'),
                  name: any(named: 'name'),
                  parentFolderId: any(named: 'parentFolderId')))
              .thenAnswer((invocation) async => []);

          when(() => mockFolderRepository.existingFilesWithName(
                  driveId: any(named: 'driveId'),
                  name: any(named: 'name'),
                  parentFolderId: any(named: 'parentFolderId')))
              .thenAnswer((invocation) async => []);
        });

        test('Returns false when no name conflict is found', () async {
          final result =
              await repository.checkNameConflictAndReturnExistingFileId(
            driveId: 'drive123',
            name: 'manifest.json',
            parentFolderId: 'folder123',
          );

          expect(result, (false, null));
        });

        test('Handles error when checking for name conflict', () async {
          when(() => mockFolderRepository.existingFoldersWithName(
                  driveId: any(named: 'driveId'),
                  name: any(named: 'name'),
                  parentFolderId: any(named: 'parentFolderId')))
              .thenThrow(Exception('Error checking for folder name conflict'));

          expect(
            () => repository.checkNameConflictAndReturnExistingFileId(
              driveId: 'drive123',
              name: 'manifest.json',
              parentFolderId: 'folder123',
            ),
            throwsA(isA<ManifestCreationException>()),
          );
        });

        test('Handles error when checking for name conflict', () async {
          when(() => mockFolderRepository.existingFilesWithName(
                  driveId: any(named: 'driveId'),
                  name: any(named: 'name'),
                  parentFolderId: any(named: 'parentFolderId')))
              .thenThrow(Exception('Error checking for file name conflict'));

          expect(
            () => repository.checkNameConflictAndReturnExistingFileId(
              driveId: 'drive123',
              name: 'manifest.json',
              parentFolderId: 'folder123',
            ),
            throwsA(isA<ManifestCreationException>()),
          );
        });

        test('Should return true when a folder with the same name is found',
            () async {
          when(() => mockFolderRepository.existingFoldersWithName(
                  driveId: any(named: 'driveId'),
                  name: any(named: 'name'),
                  parentFolderId: any(named: 'parentFolderId')))
              .thenAnswer((invocation) async => [mockFolderEntry]);

          final result =
              await repository.checkNameConflictAndReturnExistingFileId(
            driveId: 'drive123',
            name: 'manifest.json',
            parentFolderId: 'folder123',
          );

          expect(result, (true, null));
        });

        test(
            'Should return true when a file with the same name is found and it is not a manifest file',
            () async {
          when(() => mockFolderRepository.existingFilesWithName(
                  driveId: any(named: 'driveId'),
                  name: any(named: 'name'),
                  parentFolderId: any(named: 'parentFolderId')))
              .thenAnswer((invocation) async => [mockFileEntry]);

          /// json
          when(() => mockFileEntry.dataContentType)
              .thenReturn(ContentType.json);

          final result =
              await repository.checkNameConflictAndReturnExistingFileId(
            driveId: 'drive123',
            name: 'manifest.json',
            parentFolderId: 'folder123',
          );

          expect(result, (true, null));
        });

        test(
            'Should return false when a file with the same name is found and it is a manifest file',
            () async {
          when(() => mockFolderRepository.existingFilesWithName(
                  driveId: any(named: 'driveId'),
                  name: any(named: 'name'),
                  parentFolderId: any(named: 'parentFolderId')))
              .thenAnswer((invocation) async => [mockFileEntry]);

          /// manifest
          when(() => mockFileEntry.dataContentType)
              .thenReturn(ContentType.manifest);
          when(() => mockFileEntry.id).thenReturn('file123');

          final result =
              await repository.checkNameConflictAndReturnExistingFileId(
            driveId: 'drive123',
            name: 'manifest.json',
            parentFolderId: 'folder123',
          );

          expect(result, (false, 'file123'));
        });
      });
    },
  );
}

class MockArnsRepository extends Mock implements ARNSRepository {}
