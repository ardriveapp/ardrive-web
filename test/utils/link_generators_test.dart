import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/link_generators.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('link generators tests', () {
    group('drive share link generator tests', () {
      late Drive testPublicDrive;
      late Drive testPrivateDrive;
      late String testPrivateDriveKeyBase64;
      late SecretKey testPrivateDriveKey;
      setUp(() {
        testPublicDrive = Drive(
          id: 'publicDriveId',
          rootFolderId: 'publicDriveRootFolderId',
          ownerAddress: 'ownerAddress',
          name: 'testPublicDrive',
          privacy: DrivePrivacy.public,
          dateCreated: DateTime.now(),
          lastUpdated: DateTime.now(),
        );
        testPrivateDrive = Drive(
          id: 'privateDriveId',
          rootFolderId: 'privateRootFolderId',
          ownerAddress: 'ownerAddress',
          name: 'testPrivateDrive',
          privacy: DrivePrivacy.private,
          dateCreated: DateTime.now(),
          lastUpdated: DateTime.now(),
        );
        testPrivateDriveKeyBase64 =
            'X123YZAB-CD4e5fgHIjKlmN6O7pqrStuVwxYzaBcd8E';
        testPrivateDriveKey =
            SecretKey(decodeBase64ToBytes(testPrivateDriveKeyBase64));
      });
      test(
          'generatePrivateDriveShareLink generates the correct link for a private drive',
          () async {
        final webShareUri = await generatePrivateDriveShareLink(
          driveId: testPrivateDrive.id,
          driveName: testPrivateDrive.name,
          driveKey: testPrivateDriveKey,
        );
        // Remove # delimiter as it messes with Uri parsing outside of app route
        // information parser
        final driveShareLink = Uri.parse(
          webShareUri.toString().replaceAll('/#', ''),
        );
        final driveId = driveShareLink.pathSegments.last;
        final driveName = driveShareLink.queryParameters['name'];
        final driveKey = driveShareLink.queryParameters['driveKey'];

        expect(driveId, equals(testPrivateDrive.id));
        expect(driveName, equals(testPrivateDrive.name));
        expect(driveKey, equals(testPrivateDriveKeyBase64));
      });
      test(
          'generatePublicDriveShareLink generates the correct link for a public drive',
          () async {
        final webShareUri = generatePublicDriveShareLink(
          driveId: testPublicDrive.id,
          driveName: testPublicDrive.name,
        );
        // Remove # delimiter as it messes with Uri parsing outside of app route
        // information parser
        final driveShareLink = Uri.parse(
          webShareUri.toString().replaceAll('/#', ''),
        );
        final driveId = driveShareLink.pathSegments.last;
        final driveName = driveShareLink.queryParameters['name'];

        expect(driveId, equals(testPublicDrive.id));
        expect(driveName, equals(testPublicDrive.name));
      });
    });

    group('file share link generator tests', () {
      late FileEntry testFile;
      late String testFileKeyBase64;
      late SecretKey testFileKey;
      setUp(() {
        testFile = FileEntry(
          id: 'testFileId',
          driveId: 'driveId',
          parentFolderId: 'parentFolderId',
          name: 'testFile',
          path: '/test/test',
          dataTxId: 'Data',
          size: 500,
          dateCreated: DateTime.now(),
          lastModifiedDate: DateTime.now(),
          lastUpdated: DateTime.now(),
          dataContentType: '',
        );
        testFileKeyBase64 = 'X123YZAB-CD4e5fgHIjKlmN6O7pqrStuVwxYzaBcd8E';
        testFileKey = SecretKey(decodeBase64ToBytes(testFileKeyBase64));
      });
      test(
          'generatePrivateFileShareLink generates the correct link for a private file',
          () async {
        final webShareUri = await generatePrivateFileShareLink(
          fileId: testFile.id,
          fileKey: testFileKey,
        );
        // Remove # delimiter as it messes with Uri parsing outside of app route
        // information parser
        final fileShareLink = Uri.parse(
          webShareUri.toString().replaceAll('/#', ''),
        );
        final fileId = fileShareLink.pathSegments[1];
        final fileKey = fileShareLink.queryParameters['fileKey'];

        expect(fileId, equals(testFile.id));
        expect(fileKey, equals(testFileKeyBase64));
      });
      test('generateFileShareLink generates the correct link for a public file',
          () async {
        final webShareUri = generatePublicFileShareLink(
          fileId: testFile.id,
        );
        // Remove # delimiter as it messes with Uri parsing outside of app route
        // information parser
        final fileShareLink = Uri.parse(
          webShareUri.toString().replaceAll('/#', ''),
        );
        final fileId = fileShareLink.pathSegments[1];

        expect(fileId, equals(testFile.id));
      });
    });
  });
}
