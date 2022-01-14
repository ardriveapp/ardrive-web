import 'package:ardrive/entities/constants.dart';
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
