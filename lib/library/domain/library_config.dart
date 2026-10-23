import 'dart:convert';

import 'package:ardrive/library/domain/library_mode.dart';
import 'package:ardrive_utils/ardrive_utils.dart'
    show DrivePrivacyTag, EntityTag;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// A library page's settings, from its `library.json` (docs/LIBRARY_PAGES.md,
/// "`library.json`").
///
/// The file is as trustworthy as the page that serves it, and no more. The
/// parser therefore refuses anything that would send the app somewhere other
/// than the page's own manifest and gateway, or open a drive other than the
/// one it names: ids must be ids, paths must be plain relative paths, and a
/// private library must carry the cipher tags its snapshot is sealed with.
///
/// Text the owner typed (title, description) is kept exactly as written. It
/// is only ever shown as plain text, so markup in it stays markup.
@immutable
class LibraryConfig extends Equatable {
  const LibraryConfig({
    required this.version,
    required this.driveId,
    required this.rootFolderId,
    required this.scope,
    required this.privacy,
    required this.owner,
    required this.snapshot,
    required this.title,
    required this.description,
    required this.images,
    required this.publishedAt,
    required this.viewer,
  });

  /// The newest `library.json` version this build reads. A page written for a
  /// newer one shows "This library needs a newer ArDrive".
  static const supportedVersion = 1;

  final int version;
  final String driveId;
  final String rootFolderId;
  final LibraryScope scope;

  /// `public` or `private` ([DrivePrivacyTag]).
  final String privacy;

  /// The address the drive and its snapshot belong to. The importer refuses a
  /// snapshot uploaded by anyone else.
  final String owner;
  final LibrarySnapshot snapshot;
  final String title;
  final String description;
  final LibraryImages images;
  final DateTime? publishedAt;
  final LibraryViewer? viewer;

  bool get isPrivate => privacy == DrivePrivacyTag.private;

  /// The folder the library opens at: the drive's root, or the published
  /// folder.
  String get scopeRootFolderId => switch (scope) {
        LibraryDriveScope() => rootFolderId,
        LibraryFolderScope(:final folderId) => folderId,
      };

  /// Parses `library.json`'s text. Throws [LibraryConfigException].
  static LibraryConfig parse(String source) {
    final Object? decoded;
    try {
      decoded = json.decode(source);
    } on FormatException catch (e) {
      throw LibraryConfigException.invalid('not JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw LibraryConfigException.invalid('not a JSON object');
    }
    return LibraryConfig.fromJson(decoded);
  }

  /// Throws [LibraryConfigException].
  factory LibraryConfig.fromJson(Map<String, dynamic> json) {
    // The version first: a newer page may have changed any other field, and
    // "needs a newer ArDrive" is the true answer even when the rest would not
    // parse here.
    final version = json['version'];
    if (version is! int || version < 1) {
      throw LibraryConfigException.invalid(
          'version must be a positive integer');
    }
    if (version > supportedVersion) {
      throw LibraryConfigException.unsupportedVersion(version);
    }

    final privacy = _string(json, 'privacy');
    if (privacy != DrivePrivacyTag.public &&
        privacy != DrivePrivacyTag.private) {
      throw LibraryConfigException.invalid(
          'privacy must be "public" or "private"');
    }

    final snapshot = LibrarySnapshot._fromJson(_map(json, 'snapshot'));
    final sealed = snapshot.tags.containsKey(EntityTag.cipher) &&
        snapshot.tags.containsKey(EntityTag.cipherIv);
    final anyCipherTag = snapshot.tags.containsKey(EntityTag.cipher) ||
        snapshot.tags.containsKey(EntityTag.cipherIv);
    if (privacy == DrivePrivacyTag.private && !sealed) {
      throw LibraryConfigException.invalid(
          'a private library needs the snapshot\'s Cipher and Cipher-IV tags');
    }
    if (privacy == DrivePrivacyTag.public && anyCipherTag) {
      throw LibraryConfigException.invalid(
          'a public library\'s snapshot cannot carry cipher tags');
    }

    final title = _string(json, 'title').trim();
    if (title.isEmpty) {
      throw LibraryConfigException.invalid('title is empty');
    }

    return LibraryConfig(
      version: version,
      driveId: _id(json, 'driveId'),
      rootFolderId: _id(json, 'rootFolderId'),
      scope: LibraryScope._fromJson(_map(json, 'scope')),
      privacy: privacy,
      owner: _address(json, 'owner'),
      snapshot: snapshot,
      title: title,
      description: _optionalString(json, 'description') ?? '',
      images: LibraryImages._fromJson(json['images']),
      publishedAt: _optionalDate(json, 'publishedAt'),
      viewer: LibraryViewer._fromJson(json['viewer']),
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
        snapshot,
        title,
        description,
        images,
        publishedAt,
        viewer,
      ];
}

/// What a library shows: a whole drive, or one folder and what is under it.
@immutable
sealed class LibraryScope extends Equatable {
  const LibraryScope();

  static LibraryScope _fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'drive':
        return const LibraryDriveScope();
      case 'folder':
        return LibraryFolderScope(_id(json, 'folderId', where: 'scope'));
      default:
        throw LibraryConfigException.invalid(
            'scope.type must be "drive" or "folder"');
    }
  }
}

class LibraryDriveScope extends LibraryScope {
  const LibraryDriveScope();

  @override
  List<Object?> get props => const [];
}

class LibraryFolderScope extends LibraryScope {
  const LibraryFolderScope(this.folderId);

  final String folderId;

  @override
  List<Object?> get props => [folderId];
}

/// The drive state artifact a library is built from, and the tags the
/// importer would otherwise read from GraphQL.
@immutable
class LibrarySnapshot extends Equatable {
  const LibrarySnapshot({
    required this.path,
    required this.txId,
    required this.tags,
  });

  /// Where the artifact is in the page's manifest.
  final String path;

  /// The artifact's own transaction, which its tags and owner belong to.
  final String txId;
  final Map<String, String> tags;

  factory LibrarySnapshot._fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    if (rawTags is! Map<String, dynamic>) {
      throw LibraryConfigException.invalid('snapshot.tags must be an object');
    }
    final tags = <String, String>{};
    for (final entry in rawTags.entries) {
      final value = entry.value;
      if (value is! String) {
        throw LibraryConfigException.invalid(
            'snapshot.tags.${entry.key} must be a string');
      }
      tags[entry.key] = value;
    }
    return LibrarySnapshot(
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
class LibraryImages extends Equatable {
  const LibraryImages({this.icon, this.social, this.cover});

  final String? icon;
  final String? social;
  final String? cover;

  factory LibraryImages._fromJson(Object? json) {
    if (json == null) return const LibraryImages();
    if (json is! Map<String, dynamic>) {
      throw LibraryConfigException.invalid('images must be an object');
    }
    String? image(String key) =>
        json[key] == null ? null : _relativePath(json, key, where: 'images');
    return LibraryImages(
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
class LibraryViewer extends Equatable {
  const LibraryViewer({required this.release, required this.manifest});

  final String release;
  final String manifest;

  static LibraryViewer? _fromJson(Object? json) {
    if (json == null) return null;
    if (json is! Map<String, dynamic>) {
      throw LibraryConfigException.invalid('viewer must be an object');
    }
    return LibraryViewer(
      release: _string(json, 'release', where: 'viewer'),
      manifest: _address(json, 'manifest', where: 'viewer'),
    );
  }

  @override
  List<Object?> get props => [release, manifest];
}

enum LibraryConfigError {
  /// Missing, malformed or unsafe: "This library can't be opened".
  invalid,

  /// Written for a newer viewer: "This library needs a newer ArDrive".
  unsupportedVersion,
}

class LibraryConfigException implements Exception {
  const LibraryConfigException._(this.error, this.message);

  LibraryConfigException.invalid(String message)
      : this._(LibraryConfigError.invalid, message);

  LibraryConfigException.unsupportedVersion(int version)
      : this._(
          LibraryConfigError.unsupportedVersion,
          'library.json version $version is newer than the '
          '${LibraryConfig.supportedVersion} this viewer reads',
        );

  final LibraryConfigError error;
  final String message;

  @override
  String toString() => 'LibraryConfigException($error): $message';
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
    throw LibraryConfigException.invalid('$key must be an object');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key, {String? where}) {
  final value = json[key];
  if (value is! String) {
    throw LibraryConfigException.invalid(
        '${_field(key, where)} must be a string');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw LibraryConfigException.invalid('$key must be a string');
  }
  return value;
}

String _id(Map<String, dynamic> json, String key, {String? where}) {
  final value = _string(json, key, where: where);
  if (!_uuid.hasMatch(value)) {
    throw LibraryConfigException.invalid(
        '${_field(key, where)} is not an ArFS id');
  }
  return value;
}

String _address(Map<String, dynamic> json, String key, {String? where}) {
  final value = _string(json, key, where: where);
  if (!_base64Url43.hasMatch(value)) {
    throw LibraryConfigException.invalid(
        '${_field(key, where)} is not a 43-character Arweave id');
  }
  return value;
}

String _relativePath(Map<String, dynamic> json, String key, {String? where}) {
  final value = _string(json, key, where: where);
  if (!isPlainRelativePath(value)) {
    throw LibraryConfigException.invalid(
        '${_field(key, where)} must be a path inside the page');
  }
  return value;
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  final value = _optionalString(json, key);
  if (value == null) return null;
  final date = DateTime.tryParse(value);
  if (date == null) {
    throw LibraryConfigException.invalid('$key is not an ISO 8601 date');
  }
  return date.toUtc();
}
