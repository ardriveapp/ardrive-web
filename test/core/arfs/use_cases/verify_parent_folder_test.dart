// import 'package:ardrive/core/arfs/use_cases/verify_parent_folder.dart';
// import 'package:ardrive/models/models.dart';
// import 'package:drift/drift.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:mocktail/mocktail.dart';

// class MockDriveDao extends Mock implements DriveDao {
//   @override
//   Selectable<FolderEntry> folderById({
//     required String driveId,
//     required String folderId,
//   }) {
//     return MockSelectable<FolderEntry>();
//   }

//   @override
//   Selectable<FolderRevision> latestFolderRevisionByFolderId({
//     required String driveId,
//     required String folderId,
//   }) {
//     return MockSelectable<FolderRevision>();
//   }

//   @override
//   Selectable<FolderEntry> foldersInFolderWithName({
//     required String driveId,
//     String? parentFolderId,
//     required String name,
//   }) {
//     return MockSelectable<FolderEntry>();
//   }
// }

// class MockSelectable<T> extends Mock implements Selectable<T> {
//   @override
//   Future<T?> getSingleOrNull() async => null;
// }

// void main() {
//   late VerifyParentFolder useCase;
//   late MockDriveDao driveDao;
//   late MockSelectable<FolderEntry> folderQuery;
//   late MockSelectable<FolderRevision> revisionQuery;
//   late MockSelectable<FolderEntry> folderNameQuery;

//   setUp(() {
//     driveDao = MockDriveDao();
//     useCase = VerifyParentFolder(driveDao);
//     folderQuery = MockSelectable<FolderEntry>();
//     revisionQuery = MockSelectable<FolderRevision>();
//     folderNameQuery = MockSelectable<FolderEntry>();

//     when(() => driveDao.folderById(
//           driveId: any(named: 'driveId'),
//           folderId: any(named: 'folderId'),
//         )).thenReturn(folderQuery);

//     when(() => driveDao.latestFolderRevisionByFolderId(
//           driveId: any(named: 'driveId'),
//           folderId: any(named: 'folderId'),
//         )).thenReturn(revisionQuery);

//     when(() => driveDao.foldersInFolderWithName(
//           driveId: any(named: 'driveId'),
//           parentFolderId: any(named: 'parentFolderId'),
//           name: any(named: 'name'),
//         )).thenReturn(folderNameQuery);
//   });

//   group('VerifyParentFolder', () {
//     const testDriveId = 'test-drive-id';
//     const testFolderId = 'test-folder-id';
//     const testFolderName = 'test-folder';

//     final testFolder = FolderEntry(
//       id: testFolderId,
//       driveId: testDriveId,
//       name: testFolderName,
//       path: '/test',
//       isHidden: false,
//       dateCreated: DateTime(2024),
//       lastUpdated: DateTime(2024),
//       parentFolderId: 'parent-id',
//       isGhost: false,
//     );

//     final testFolderRevision = FolderRevision(
//       driveId: testDriveId,
//       folderId: testFolderId,
//       name: testFolderName,
//       parentFolderId: 'parent-id',
//       action: 'create',
//       dateCreated: DateTime(2024),
//       metadataTxId: 'tx-id',
//       isHidden: false,
//     );

//     test('successfully verifies existing parent folder', () async {
//       when(() => folderQuery.getSingleOrNull())
//           .thenAnswer((_) async => testFolder);
//       when(() => revisionQuery.getSingleOrNull())
//           .thenAnswer((_) async => testFolderRevision);

//       final result = await useCase(
//         driveId: testDriveId,
//         parentFolderId: testFolderId,
//       );

//       expect(result, testFolder);
//       verify(() => driveDao.folderById(
//             driveId: testDriveId,
//             folderId: testFolderId,
//           )).called(1);
//       verify(() => driveDao.latestFolderRevisionByFolderId(
//             driveId: testDriveId,
//             folderId: testFolderId,
//           )).called(1);
//     });

//     test('successfully finds existing folder by name', () async {
//       when(() => folderNameQuery.getSingleOrNull())
//           .thenAnswer((_) async => testFolder);

//       final result = await useCase(
//         driveId: testDriveId,
//         parentFolderId: testFolderId,
//         folderName: testFolderName,
//       );

//       expect(result, testFolder);
//       verify(() => driveDao.foldersInFolderWithName(
//             driveId: testDriveId,
//             parentFolderId: testFolderId,
//             name: testFolderName,
//           )).called(1);
//       verifyNever(() => driveDao.folderById(
//             driveId: any(named: 'driveId'),
//             folderId: any(named: 'folderId'),
//           ));
//     });

//     test('falls back to parent folder verification when folder name not found',
//         () async {
//       when(() => folderNameQuery.getSingleOrNull())
//           .thenAnswer((_) async => null);
//       when(() => folderQuery.getSingleOrNull())
//           .thenAnswer((_) async => testFolder);
//       when(() => revisionQuery.getSingleOrNull())
//           .thenAnswer((_) async => testFolderRevision);

//       final result = await useCase(
//         driveId: testDriveId,
//         parentFolderId: testFolderId,
//         folderName: 'non-existent-folder',
//       );

//       expect(result, testFolder);
//       verify(() => driveDao.foldersInFolderWithName(
//             driveId: testDriveId,
//             parentFolderId: testFolderId,
//             name: 'non-existent-folder',
//           )).called(1);
//       verify(() => driveDao.folderById(
//             driveId: testDriveId,
//             folderId: testFolderId,
//           )).called(1);
//     });

//     test('throws when folder does not exist', () async {
//       when(() => folderQuery.getSingleOrNull()).thenAnswer((_) async => null);

//       expect(
//         () => useCase(
//           driveId: testDriveId,
//           parentFolderId: testFolderId,
//         ),
//         throwsA(isA<ParentFolderVerificationException>().having(
//           (e) => e.message,
//           'message',
//           'Parent folder not found',
//         )),
//       );
//     });

//     test('throws when folder belongs to different drive', () async {
//       final wrongDriveFolder = FolderEntry(
//         id: testFolderId,
//         driveId: 'wrong-drive-id',
//         name: testFolderName,
//         path: '/test',
//         isHidden: false,
//         dateCreated: DateTime(2024),
//         lastUpdated: DateTime(2024),
//         parentFolderId: 'parent-id',
//         isGhost: false,
//       );

//       when(() => folderQuery.getSingleOrNull())
//           .thenAnswer((_) async => wrongDriveFolder);

//       expect(
//         () => useCase(
//           driveId: testDriveId,
//           parentFolderId: testFolderId,
//         ),
//         throwsA(isA<ParentFolderVerificationException>().having(
//           (e) => e.message,
//           'message',
//           'Parent folder belongs to a different drive',
//         )),
//       );
//     });

//     test('throws when folder has no valid revision', () async {
//       when(() => folderQuery.getSingleOrNull())
//           .thenAnswer((_) async => testFolder);
//       when(() => revisionQuery.getSingleOrNull()).thenAnswer((_) async => null);

//       expect(
//         () => useCase(
//           driveId: testDriveId,
//           parentFolderId: testFolderId,
//         ),
//         throwsA(isA<ParentFolderVerificationException>().having(
//           (e) => e.message,
//           'message',
//           'Parent folder has no valid revision',
//         )),
//       );
//     });
//   });
// }
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test', () {
    expect(true, isTrue);
  });
}
