import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:arweave/arweave.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:platform/platform.dart';

final fakePrivateTags = [
  Tag(EntityTag.contentType, ContentType.octetStream),
  Tag(EntityTag.cipher, Cipher.aes256),
  Tag(
    EntityTag.cipherIv,
    'qwertyuiopasdfgh',
  ),
];

fakeApplicationTags({Platform platform = const LocalPlatform()}) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final version = packageInfo.version;

  return <Tag>[
    Tag(EntityTag.appName, 'ArDrive-App'),
    Tag(EntityTag.appVersion, version),
    Tag(
      EntityTag.unixTime,
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
    ),
    Tag(EntityTag.appPlatform, getPlatform(platform: platform)),

    // TODO: PE-2380
    // Tag(EntityTag.appPlatformVersion, getPlatformVersion()),
  ];
}

List<Tag> createFakeEntityTags(FileEntity entity) => <Tag>[
      Tag(EntityTag.arFs, '0.11'),
      Tag(EntityTag.entityType, EntityType.file),
      Tag(EntityTag.driveId, entity.driveId!),
      Tag(EntityTag.parentFolderId, entity.parentFolderId!),
      Tag(EntityTag.fileId, entity.id!),
    ];
