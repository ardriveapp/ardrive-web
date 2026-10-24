import 'dart:convert';

import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive_utils/ardrive_utils.dart'
    show DrivePrivacyTag, EntityTag;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A publication's settings, from its `publication.json` (docs/PUBLICATIONS.md,
/// "`publication.json`").
///
/// The file is as trustworthy as the page that serves it, and no more. The
/// parser therefore refuses anything that would send the app somewhere other
/// than the page's own manifest and gateway, or open a drive other than the
/// one it names: ids must be ids, paths must be plain relative paths, and a
/// private publication must carry the cipher tags its snapshot is sealed with.
///
/// Text the owner typed (title, description) is kept exactly as written. It
/// is only ever shown as plain text, so markup in it stays markup.
@immutable
class PublicationConfig extends Equatable {
  const PublicationConfig({
    required this.version,
    required this.driveId,
    required this.rootFolderId,
    required this.scope,
    required this.privacy,
    required this.owner,
    this.ownerName,
    required this.snapshot,
    required this.title,
    required this.description,
    required this.images,
    required this.publishedAt,
    required this.viewer,
  });

  /// The newest `publication.json` version this build reads. A page written for a
  /// newer one shows "This page needs a newer ArDrive".
  static const supportedVersion = 1;

  final int version;
  final String driveId;
  final String rootFolderId;
  final PublicationScope scope;

  /// `public` or `private` ([DrivePrivacyTag]).
  final String privacy;

  /// The address the drive and its snapshot belong to. The importer refuses a
  /// snapshot uploaded by anyone else.
  final String owner;

  /// The name the owner chose to be shown by, if any. Typed, like the title,
  /// so it is a claim and not a proof: the page shows [owner] beside it.
  final String? ownerName;
  final PublicationSnapshot snapshot;
  final String title;
  final String description;
  final PublicationImages images;
  final DateTime? publishedAt;
  final PublicationViewer? viewer;

  bool get isPrivate => privacy == DrivePrivacyTag.private;

  /// The folder the publication opens at: the drive's root, or the published
  /// folder.
  String get scopeRootFolderId => switch (scope) {
        PublicationDriveScope() => rootFolderId,
        PublicationFolderScope(:final folderId) => folderId,
      };

  /// Parses `publication.json`'s text. Throws [PublicationConfigException].
  static PublicationConfig parse(String source) {
    final Object? decoded;
    try {
      decoded = json.decode(source);
    } on FormatException catch (e) {
      throw PublicationConfigException.invalid('not JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw PublicationConfigException.invalid('not a JSON object');
    }
    return PublicationConfig.fromJson(decoded);
  }

  /// Throws [PublicationConfigException].
  factory PublicationConfig.fromJson(Map<String, dynamic> json) {
    // The version first: a newer page may have changed any other field, and
    // "needs a newer ArDrive" is the true answer even when the rest would not
    // parse here.
    final version = json['version'];
    if (version is! int || version < 1) {
      throw PublicationConfigException.invalid(
          'version must be a positive integer');
    }
    if (version > supportedVersion) {
      throw PublicationConfigException.unsupportedVersion(version);
    }

    final privacy = _string(json, 'privacy');
    if (privacy != DrivePrivacyTag.public &&
        privacy != DrivePrivacyTag.private) {
      throw PublicationConfigException.invalid(
          'privacy must be "public" or "private"');
    }

    final snapshot = PublicationSnapshot._fromJson(_map(json, 'snapshot'));
    final sealed = snapshot.tags.containsKey(EntityTag.cipher) &&
        snapshot.tags.containsKey(EntityTag.cipherIv);
    final anyCipherTag = snapshot.tags.containsKey(EntityTag.cipher) ||
        snapshot.tags.containsKey(EntityTag.cipherIv);
    if (privacy == DrivePrivacyTag.private && !sealed) {
      throw PublicationConfigException.invalid(
          'a private publication needs the snapshot\'s Cipher and Cipher-IV tags');
    }
    if (privacy == DrivePrivacyTag.public && anyCipherTag) {
      throw PublicationConfigException.invalid(
          'a public publication\'s snapshot cannot carry cipher tags');
    }

    final title = _string(json, 'title').trim();
    if (title.isEmpty) {
      throw PublicationConfigException.invalid('title is empty');
    }

    return PublicationConfig(
      version: version,
      driveId: _id(json, 'driveId'),
      rootFolderId: _id(json, 'rootFolderId'),
      scope: PublicationScope._fromJson(_map(json, 'scope')),
      privacy: privacy,
      owner: _address(json, 'owner'),
      ownerName: _nonEmpty(_optionalString(json, 'ownerName')),
      snapshot: snapshot,
      title: title,
      description: _optionalString(json, 'description') ?? '',
      images: PublicationImages._fromJson(json['images']),
      publishedAt: _optionalDate(json, 'publishedAt'),
      viewer: PublicationViewer._fromJson(json['viewer']),
    );
  }

  @override
  List<Object?> get props => [
        version,
        driveId,
        rootFolderId,
        scope,
        privacy,
        owner,
        ownerName,
        snapshot,
        title,
        description,
        images,
        publishedAt,
        viewer,
      ];
}

/// What a publication shows: a whole drive, or one folder and what is under it.
@immutable
sealed class PublicationScope extends Equatable {
  const PublicationScope();

  static PublicationScope _fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'drive':
        return const PublicationDriveScope();
      case 'folder':
        return PublicationFolderScope(_id(json, 'folderId', where: 'scope'));
      default:
        throw PublicationConfigException.invalid(
            'scope.type must be "drive" or "folder"');
    }
  }
}

class PublicationDriveScope extends PublicationScope {
  const PublicationDriveScope();

  @override
  List<Object?> get props => const [];
}

class PublicationFolderScope extends PublicationScope {
  const PublicationFolderScope(this.folderId);

  final String folderId;

  @override
  List<Object?> get props => [folderId];
}

/// The drive state artifact a publication is built from, and the tags the
/// importer would otherwise read from GraphQL.
@immutable
class PublicationSnapshot extends Equatable {
  const PublicationSnapshot({
    required this.path,
    required this.txId,
    required this.tags,
  });

  /// Where the artifact is in the page's manifest.
  final String path;

  /// The artifact's own transaction, which its tags and owner belong to.
  final String txId;
  final Map<String, String> tags;

  factory PublicationSnapshot._fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    if (rawTags is! Map<String, dynamic>) {
      throw PublicationConfigException.invalid(
          'snapshot.tags must be an object');
    }
    final tags = <String, String>{};
    for (final entry in rawTags.entries) {
      final value = entry.value;
      if (value is! String) {
        throw PublicationConfigException.invalid(
            'snapshot.tags.${entry.key} must be a string');
      }
      tags[entry.key] = value;
    }
    return PublicationSnapshot(
      path: _relativePath(json, 'path', where: 'snapshot'),
      txId: _address(json, 'txId', where: 'snapshot'),
      tags: Map.unmodifiable(tags),
    );
  }

  @override
  List<Object?> get props => [path, txId, tags];
}

/// The page's images, each a path in the page's manifest, or null when the
/// owner did not set one.
@immutable
class PublicationImages extends Equatable {
  const PublicationImages({this.icon, this.social, this.cover});

  final String? icon;
  final String? social;
  final String? cover;

  factory PublicationImages._fromJson(Object? json) {
    if (json == null) return const PublicationImages();
    if (json is! Map<String, dynamic>) {
      throw PublicationConfigException.invalid('images must be an object');
    }
    String? image(String key) =>
        json[key] == null ? null : _relativePath(json, key, where: 'images');
    return PublicationImages(
      icon: image('icon'),
      social: image('social'),
      cover: image('cover'),
    );
  }

  @override
  List<Object?> get props => [icon, social, cover];
}

/// The ArDrive release the page was published to run, for the record.
@immutable
class PublicationViewer extends Equatable {
  const PublicationViewer({required this.release, required this.manifest});

  final String release;
  final String manifest;

  static PublicationViewer? _fromJson(Object? json) {
    if (json == null) return null;
    if (json is! Map<String, dynamic>) {
      throw PublicationConfigException.invalid('viewer must be an object');
    }
    return PublicationViewer(
      release: _string(json, 'release', where: 'viewer'),
      manifest: _address(json, 'manifest', where: 'viewer'),
    );
  }

  @override
  List<Object?> get props => [release, manifest];
}

enum PublicationConfigError {
  /// Missing, malformed or unsafe: "This page can't be opened".
  invalid,

  /// Written for a newer viewer: "This page needs a newer ArDrive".
  unsupportedVersion,
}

class PublicationConfigException implements Exception {
  const PublicationConfigException._(this.error, this.message);

  PublicationConfigException.invalid(String message)
      : this._(PublicationConfigError.invalid, message);

  PublicationConfigException.unsupportedVersion(int version)
      : this._(
          PublicationConfigError.unsupportedVersion,
          'publication.json version $version is newer than the '
          '${PublicationConfig.supportedVersion} this viewer reads',
        );

  final PublicationConfigError error;
  final String message;

  @override
  String toString() => 'PublicationConfigException($error): $message';
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// A transaction id or an Arweave address: 43 base64url characters.
final _base64Url43 = RegExp(r'^[A-Za-z0-9_-]{43}$');

String _field(String key, String? where) => where == null ? key : '$where.$key';

Map<String, dynamic> _map(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map<String, dynamic>) {
    throw PublicationConfigException.invalid('$key must be an object');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key, {String? where}) {
  final value = json[key];
  if (value is! String) {
    throw PublicationConfigException.invalid(
        '${_field(key, where)} must be a string');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw PublicationConfigException.invalid('$key must be a string');
  }
  return value;
}

String _id(Map<String, dynamic> json, String key, {String? where}) {
  final value = _string(json, key, where: where);
  if (!_uuid.hasMatch(value)) {
    throw PublicationConfigException.invalid(
        '${_field(key, where)} is not an ArFS id');
  }
  return value;
}

String _address(Map<String, dynamic> json, String key, {String? where}) {
  final value = _string(json, key, where: where);
  if (!_base64Url43.hasMatch(value)) {
    throw PublicationConfigException.invalid(
        '${_field(key, where)} is not a 43-character Arweave id');
  }
  return value;
}

String _relativePath(Map<String, dynamic> json, String key, {String? where}) {
  final value = _string(json, key, where: where);
  if (!isPlainRelativePath(value)) {
    throw PublicationConfigException.invalid(
        '${_field(key, where)} must be a path inside the page');
  }
  return value;
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  final value = _optionalString(json, key);
  if (value == null) return null;
  final date = DateTime.tryParse(value);
  if (date == null) {
    throw PublicationConfigException.invalid('$key is not an ISO 8601 date');
  }
  return date.toUtc();
}

String? _nonEmpty(String? text) {
  final trimmed = text?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
