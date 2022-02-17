import 'package:ardrive/entities/entities.dart';
import 'package:arweave/arweave.dart';

final fakePrivateTags = [
  Tag(EntityTag.contentType, ContentType.octetStream),
  Tag(EntityTag.cipher, Cipher.aes256),
  Tag(
    EntityTag.cipherIv,
    'qwertyuiopasdfgh',
  ),
];

final fakeApplicationTags = [
  Tag(EntityTag.appName, 'ArDrive-Web'),
  Tag(EntityTag.appVersion, '0.0.0'),
  Tag(EntityTag.unixTime,
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString())
];

List<Tag> createFakeEntityTags(FileEntity entity) => <Tag>[
      Tag(EntityTag.arFs, '0.11'),
      Tag(EntityTag.entityType, EntityType.file),
      Tag(EntityTag.driveId, entity.driveId!),
      Tag(EntityTag.parentFolderId, entity.parentFolderId!),
      Tag(EntityTag.fileId, entity.id!),
    ];
