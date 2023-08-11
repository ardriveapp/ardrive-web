import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/utils/custom_metadata.dart';

import './database/database.dart';

extension DriveExtensions on Drive {
  bool get isPublic => privacy == DrivePrivacy.public;
  bool get isPrivate => privacy == DrivePrivacy.private;

  DriveEntity asEntity() {
    final drive = DriveEntity(
      id: id,
      name: name,
      rootFolderId: rootFolderId,
      privacy: privacy,
      authMode: privacy == DrivePrivacy.private
          ? DriveAuthMode.password
          : DriveAuthMode.none,
    );

    drive.customJsonMetadata = parseCustomJsonMetadata(customJsonMetadata);
    drive.customGqlTags = parseCustomGqlTags(customGQLTags);

    return drive;
  }
}
