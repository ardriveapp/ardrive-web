import 'package:ardrive/blocs/drive_detail/utils/breadcrumb_builder.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart'; // Adjust if necessary
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

class FakeBreadCrumbRowInfo extends Fake implements BreadCrumbRowInfo {}

void main() {
  group('BreadcrumbBuilder Tests', () {
    late MockFolderRepository mockFolderRepository;
    late BreadcrumbBuilder breadcrumbBuilder;

    setUp(() {
      mockFolderRepository = MockFolderRepository();
      breadcrumbBuilder = BreadcrumbBuilder(mockFolderRepository);

      // Register fallback values
      registerFallbackValue(FakeBreadCrumbRowInfo());
    });

    test('returns empty breadcrumbs for root folder', () async {
      final breadcrumbs = await breadcrumbBuilder.buildForFolder(
        folderId: 'rootFolderId',
        rootFolderId: 'rootFolderId',
        driveId: 'driveId',
      );

      expect(breadcrumbs, isEmpty);
    });

    test('returns single breadcrumb for single folder', () async {
      when(() => mockFolderRepository.getLatestFolderRevisionInfo(any(), any()))
          .thenAnswer((_) async => FolderRevision(
                folderId: 'folderId',
                driveId: 'driveId',
                name: 'Folder',
                metadataTxId: 'metaTxId',
                dateCreated: DateTime.now(),
                action: 'create',
                isHidden: false,
              ));

      final breadcrumbs = await breadcrumbBuilder.buildForFolder(
        folderId: 'folderId',
        rootFolderId: 'rootFolderId',
        driveId: 'driveId',
      );

      expect(breadcrumbs, hasLength(1));
      expect(breadcrumbs.first.text, 'Folder');
    });

    test('builds correct breadcrumbs for nested folders', () async {
      when(() => mockFolderRepository
              .getLatestFolderRevisionInfo('driveId', 'subFolderId'))
          .thenAnswer((_) async => FolderRevision(
                folderId: 'subFolderId',
                parentFolderId: 'parentFolderId',
                driveId: 'driveId',
                name: 'SubFolder',
                metadataTxId: 'metaTxId',
                dateCreated: DateTime.now(),
                action: 'create',
                isHidden: false,
              ));

      when(() => mockFolderRepository
              .getLatestFolderRevisionInfo('driveId', 'parentFolderId'))
          .thenAnswer((_) async => FolderRevision(
                folderId: 'parentFolderId',
                parentFolderId: 'rootFolderId', // Linking to the root folder
                driveId: 'driveId',
                name: 'ParentFolder',
                metadataTxId: 'metaTxId',
                dateCreated: DateTime.now(),
                action: 'create',
                isHidden: false,
              ));

      final breadcrumbs = await breadcrumbBuilder.buildForFolder(
        folderId: 'subFolderId',
        rootFolderId: 'rootFolderId',
        driveId: 'driveId',
      );

      expect(breadcrumbs, hasLength(2));
      expect(breadcrumbs[0].text, 'ParentFolder');
      expect(breadcrumbs[1].text, 'SubFolder');
    });

    test('throws for invalid starting folder ID', () async {
      /// Mocking the repository to return null for any folder ID
      when(() => mockFolderRepository.getLatestFolderRevisionInfo(any(), any()))
          .thenAnswer((_) async => null);

      expect(
        () => breadcrumbBuilder.buildForFolder(
          folderId: 'invalidFolderId',
          rootFolderId: 'rootFolderId',
          driveId: 'driveId',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('throws for Intermediate Missing Folder', () async {
      /// Mocking the repository to return null for any folder ID

      /// FolderC is Valid and FolderB is missing
      /// FolderA is linked to the root folder
      when(() => mockFolderRepository
              .getLatestFolderRevisionInfo('driveId', 'folderC'))
          .thenAnswer((_) async => FolderRevision(
                folderId: 'folderC',
                parentFolderId: 'folderB',
                driveId: 'driveId',
                name: 'SubFolder',
                metadataTxId: 'metaTxId',
                dateCreated: DateTime.now(),
                action: 'create',
                isHidden: false,
              ));
      when(() => mockFolderRepository.getLatestFolderRevisionInfo(
          'driveId', 'folderB')).thenAnswer((_) async => null);
      when(() => mockFolderRepository
              .getLatestFolderRevisionInfo('driveId', 'parentFolderId'))
          .thenAnswer((_) async => FolderRevision(
                folderId: 'folderA',
                parentFolderId: 'rootFolderId', // Linking to the root folder
                driveId: 'driveId',
                name: 'ParentFolder',
                metadataTxId: 'metaTxId',
                dateCreated: DateTime.now(),
                action: 'create',
                isHidden: false,
              ));

      expect(
        () => breadcrumbBuilder.buildForFolder(
          folderId: 'folderC',
          rootFolderId: 'rootFolderId',
          driveId: 'driveId',
        ),
        throwsA(isA<Exception>()),
      );
    });
    test(
        'builds correct breadcrumbs for 10 levels deep (root folder does not count)',
        () async {
      // Set up a chain of folder revisions, each pointing to its parent
      for (int i = 9; i >= 0; i--) {
        final folderRevision = FolderRevision(
          folderId: 'folderId$i',
          driveId: 'driveId',
          name: 'Folder $i',
          parentFolderId:
              i > 0 ? 'folderId${i - 1}' : null, // Linking to the parent folder
          metadataTxId: 'metaTxId$i',
          dateCreated: DateTime.now(),
          action: 'create',
          isHidden: false,
        );

        when(() => mockFolderRepository.getLatestFolderRevisionInfo(
            'driveId', 'folderId$i')).thenAnswer((_) async => folderRevision);
      }

      final breadcrumbs = await breadcrumbBuilder.buildForFolder(
        folderId: 'folderId9', // Deepest folder
        rootFolderId: 'folderId0', // Root folder
        driveId: 'driveId',
      );

      expect(breadcrumbs, hasLength(9));
      for (int i = 0; i < 9; i++) {
        expect(breadcrumbs[i].text, 'Folder ${i + 1}');
        expect(breadcrumbs[i].targetId, 'folderId${i + 1}');
      }
    });
  });
}
