import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/models/database/database.dart'; // Ensure this imports FolderRevision
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../manifest/domain/manifest_repository_test.dart';
import '../../test_utils/mocks.dart';

class MockSelectable<T> extends Mock implements drift.Selectable<T> {}

void main() {
  group('FolderRepository Tests', () {
    late MockDriveDao mockDriveDao;
    late FolderRepository folderRepository;
    late MockSelectable<FolderRevision> selectable =
        MockSelectable<FolderRevision>();
    setUp(() {
      mockDriveDao = MockDriveDao();
      folderRepository = FolderRepository(mockDriveDao);

      // Setup mock responses
      when(() => mockDriveDao.latestFolderRevisionByFolderId(
              driveId: any(named: 'driveId'), folderId: any(named: 'folderId')))
          .thenReturn(selectable); // Default case for not found
      when(() => selectable.getSingleOrNull()).thenAnswer((_) async => null);
    });

    test('getLatestFolderRevisionInfo returns a FolderRevision on valid input',
        () async {
      final expectedFolderRevision = FolderRevision(
        folderId: 'validFolderId',
        driveId: 'validDriveId',
        name: 'TestFolder',
        metadataTxId: 'meta123',
        dateCreated: DateTime.now(),
        action: 'create',
        isHidden: false,
        // Add more fields as necessary
      );

      when(() => mockDriveDao.latestFolderRevisionByFolderId(
              driveId: 'validDriveId', folderId: 'validFolderId'))
          .thenReturn(selectable); // Default case for not found
      when(() => selectable.getSingleOrNull()).thenAnswer((_) async {
        return expectedFolderRevision;
      });

      final folderRevision = await folderRepository.getLatestFolderRevisionInfo(
          'validDriveId', 'validFolderId');

      expect(folderRevision, equals(expectedFolderRevision));
      // Verify all relevant fields
      expect(folderRevision?.folderId, equals('validFolderId'));
      expect(folderRevision?.driveId, equals('validDriveId'));
      // Add more verifications as necessary
    });

    test('getLatestFolderRevisionInfo returns null when no data exists',
        () async {
      // The null setup is already done in setUp()
      final folderRevision = await folderRepository.getLatestFolderRevisionInfo(
          'invalidDriveId', 'invalidFolderId');
      expect(folderRevision, isNull);
    });
    group('getFolderNode', () {
      test('returns a FolderNode on valid input', () async {
        when(() => mockDriveDao.getFolderTree('validDriveId', 'validFolderId'))
            .thenAnswer((invocation) async => MockFolderNode());

        final folderNode = await folderRepository.getFolderNode(
          'validDriveId',
          'validFolderId',
        );

        expect(folderNode, isNotNull);
        verify(() => mockDriveDao.getFolderTree(
              'validDriveId',
              'validFolderId',
            )).called(1);
      });
    });
  });
}
