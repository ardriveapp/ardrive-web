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
          'generateDriveShareLink generates the correct link for a private drive',
          () async {
        final driveShareLink = await generateDriveShareLink(
          drive: testPrivateDrive,
          driveKey: testPrivateDriveKey,
        );
        print(driveShareLink);
        if (driveShareLink.pathSegments.length > 1) {
          final driveId = driveShareLink.pathSegments[1];
          final name = driveShareLink.queryParameters['name'];
          final driveKey = driveShareLink.queryParameters['driveKey'];

          expect(driveId, equals(testPrivateDrive.id));
        }
      });
      test(
          'generateDriveShareLink generates the correct link for a public drive',
          () {});
    });
  });
}
