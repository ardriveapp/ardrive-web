import 'package:ardrive/entities/entities.dart';
import 'package:arweave/arweave.dart';
import 'package:package_info_plus/package_info_plus.dart';

final fakePrivateTags = [
  Tag(EntityTag.contentType, ContentType.octetStream),
  Tag(EntityTag.cipher, Cipher.aes256),
  Tag(
    EntityTag.cipherIv,
    'qwertyuiopasdfgh',
  ),
];

Future<List<Tag>> fakeApplicationTags({
  required String platform,
  PackageInfo? pInfo,
}) async {
  final packageInfo = pInfo ?? await PackageInfo.fromPlatform();
  final version = packageInfo.version;

  return <Tag>[
    Tag(EntityTag.appName, 'ArDrive-App'),
    Tag(EntityTag.appVersion, version),
    Tag(
      EntityTag.unixTime,
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
    ),
    Tag(EntityTag.appPlatform, platform),
  ];
}

List<Tag> createFakeEntityTags(FileEntity entity) => <Tag>[
      Tag(EntityTag.arFs, '0.11'),
      Tag(EntityTag.entityType, EntityType.file),
      Tag(EntityTag.driveId, entity.driveId!),
      Tag(EntityTag.parentFolderId, entity.parentFolderId!),
      Tag(EntityTag.fileId, entity.id!),
    ];
