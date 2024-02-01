import 'package:ardrive/entities/entities.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';

final fakePrivateTags = [
  Tag(EntityTag.contentType, ContentType.octetStream),
  Tag(EntityTag.cipher, Cipher.aes256),
  Tag(
    EntityTag.cipherIv,
    'qwertyuiopasdfgh',
  ),
];

List<Tag> fakeApplicationTags({
  required String version,
}) {
  final String platform = AppPlatform.getPlatform().name;
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
      Tag(EntityTag.arFs, '0.12'),
      Tag(EntityTag.entityType, EntityTypeTag.file),
      Tag(EntityTag.driveId, entity.driveId!),
      Tag(EntityTag.parentFolderId, entity.parentFolderId!),
      Tag(EntityTag.fileId, entity.id!),
    ];
