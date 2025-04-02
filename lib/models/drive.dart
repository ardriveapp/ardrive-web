import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/utils/custom_metadata.dart';
import 'package:ardrive_utils/ardrive_utils.dart';

import './database/database.dart';

extension DriveExtensions on Drive {
  bool get isPublic => privacy == DrivePrivacyTag.public;
  bool get isPrivate => privacy == DrivePrivacyTag.private;

  DriveEntity asEntity() {
    final drive = DriveEntity(
      id: id,
      name: name,
      rootFolderId: rootFolderId,
      privacy: privacy,
      isHidden: isHidden,
      signatureType: signatureType,
      authMode: privacy == DrivePrivacyTag.private
          ? DriveAuthModeTag.password
          : DriveAuthModeTag.none,
    );

    drive.customJsonMetadata = parseCustomJsonMetadata(customJsonMetadata);
    drive.customGqlTags = parseCustomGqlTags(customGQLTags);

    return drive;
  }
}
