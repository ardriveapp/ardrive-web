import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:platform/platform.dart';
import 'package:test/test.dart';

import '../test_utils/fake_data.dart';
import '../test_utils/utils.dart';

void main() {
  late PackageInfo packageInfo;
  final androidFakePlatform = FakePlatform(operatingSystem: 'android');
  final iOSFakePlatform = FakePlatform(operatingSystem: 'ios');
  final unknownFakePlatform =
      FakePlatform(operatingSystem: 'not something we know');

  final appNameTag = Tag(
    encodeStringToBase64(EntityTag.appName),
    encodeStringToBase64(appName),
  );
  final appVersionTag = Tag(
    encodeStringToBase64(EntityTag.appVersion),
    encodeStringToBase64(version),
  );
  final appPlatform = Tag(
    encodeStringToBase64(EntityTag.appPlatform),
    encodeStringToBase64('unknown'),
  );

  group('Entity Application Tag Test', () {
    setUp(() async {
      PackageInfo.setMockInitialValues(
        appName: appName,
        packageName: packageName,
        version: version,
        buildNumber: buildNumber,
        buildSignature: buildSignature,
      );
      packageInfo = await PackageInfo.fromPlatform();
    });

    test('PackageInfo fetches correct app version', () async {
      expect(packageInfo.version, equals(version));
    });

    test('Transaction contains correct Application Tags', () async {
      final tx = await getTestTransaction('test/fixtures/signed_v2_tx.json');

      expect(tx.tags.isEmpty, isTrue);

      AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

      tx.addApplicationTags(
        version: packageInfo.version,
      );

      expect(tx.tags.contains(appNameTag), isTrue);
      expect(tx.tags.contains(appVersionTag), isTrue);
    });

    test('Transaction contains correct App-Platform Tags', () async {
      Transaction tx =
          await getTestTransaction('test/fixtures/signed_v2_tx.json');
      expect(tx.tags.isEmpty, isTrue);

      AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

      tx.addApplicationTags(
        version: packageInfo.version,
      );
      expect(
        tx.tags.contains(
          Tag(
            encodeStringToBase64('App-Platform'),
            encodeStringToBase64('Android'),
          ),
        ),
        isTrue,
      );

      tx = await getTestTransaction('test/fixtures/signed_v2_tx.json');
      expect(tx.tags.isEmpty, isTrue);

      AppPlatform.setMockPlatform(platform: SystemPlatform.iOS);

      tx.addApplicationTags(
        version: packageInfo.version,
      );
      expect(
        tx.tags.contains(
          Tag(
            encodeStringToBase64('App-Platform'),
            encodeStringToBase64('iOS'),
          ),
        ),
        isTrue,
      );

      tx = await getTestTransaction('test/fixtures/signed_v2_tx.json');
      expect(tx.tags.isEmpty, isTrue);

      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

      tx.addApplicationTags(
        version: packageInfo.version,
      );
      expect(
        tx.tags.contains(
          Tag(
            encodeStringToBase64('App-Platform'),
            encodeStringToBase64('unknown'),
          ),
        ),
        isTrue,
      );

      tx = await getTestTransaction('test/fixtures/signed_v2_tx.json');
      expect(tx.tags.isEmpty, isTrue);

      AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

      tx.addApplicationTags(
        version: packageInfo.version,
        isWeb: true,
      );
      expect(
        tx.tags.contains(
          Tag(
            encodeStringToBase64('App-Platform'),
            encodeStringToBase64('Web'),
          ),
        ),
        isTrue,
      );
    });

    test('File Entity contains correct Application Tags', () async {
      final fileEntity = FileEntity(
        id: testEntityId,
        driveId: driveId,
        parentFolderId: rootFolderId,
        name: testEntityName,
        size: testEntitySize,
        dataContentType: testEntityDataTxId,
        dataTxId: testEntityDataTxId,
        lastModifiedDate: DateTime.now(),
      );

      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

      final tx = await fileEntity.asTransaction();
      expect(tx.tags.contains(appNameTag), isTrue);
      expect(tx.tags.contains(appVersionTag), isTrue);
    });

    test('Folder Entity contains correct Application Tags', () async {
      final folderEntity = FolderEntity(
        id: testEntityId,
        driveId: driveId,
        parentFolderId: rootFolderId,
        name: testEntityName,
      );
      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

      final tx = await folderEntity.asTransaction();
      tx.addApplicationTags(version: packageInfo.version);

      expect(tx.tags.contains(appNameTag), isTrue);
      expect(tx.tags.contains(appVersionTag), isTrue);
    });

    test('Drive Entity contains correct Application Tags', () async {
      final driveEntity = DriveEntity(
        id: driveId,
        name: testEntityName,
        rootFolderId: rootFolderId,
        privacy: DrivePrivacy.public,
      );
      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

      final tx = await driveEntity.asTransaction();
      tx.addApplicationTags(version: packageInfo.version);

      expect(tx.tags.contains(appNameTag), isTrue);
      expect(tx.tags.contains(appVersionTag), isTrue);
    });
  });
}
