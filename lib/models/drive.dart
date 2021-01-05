import 'package:ardrive/entities/entities.dart';

import './database/database.dart';

extension DriveExtensions on Drive {
  bool get isPublic => privacy == DrivePrivacy.public;
  bool get isPrivate => privacy == DrivePrivacy.private;

  DriveEntity asEntity() => DriveEntity(
        id: id,
        name: name,
        rootFolderId: rootFolderId,
        privacy: privacy,
        authMode:
            privacy == DrivePrivacy.private ? DriveAuthMode.password : null,
      );
}
