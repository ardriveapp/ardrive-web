import 'dart:convert';

import 'package:ardrive/entities/entities.dart';
import 'package:arweave/arweave.dart';

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

    drive.customJsonMetadata =
        customJsonMetadata != null ? jsonDecode(customJsonMetadata!) : null;
    drive.customGqlTags = customGQLTags != null
        ? (jsonDecode(customGQLTags!) as List<dynamic>)
            .map((maybeTag) => Tag.fromJson(maybeTag))
            .toList()
        : null;
    return drive;
  }
}
