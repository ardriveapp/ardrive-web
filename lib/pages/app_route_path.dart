import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

@immutable
class AppRoutePath {
  /// Whether or not the user is trying to sign in.
  final bool signingIn;

  final bool getStarted;

  final String? driveId;
  final String? driveName;
  final String? driveFolderId;

  final DriveKey? sharedDriveKey;
  final String? sharedRawDriveKey;

  final String? sharedFileId;

  /// The private key of the corresponding shared file.
  final SecretKey? sharedFileKey;

  /// The private key of the corresponding shared file, encoded as Base64.
  final String? sharedRawFileKey;

  /// Whether the link carried a file key that could not be decoded.
  ///
  /// The key is dropped when that happens - links get truncated and mangled in
  /// transit all the time - so [sharedFileKey] is `null` just like it is for a
  /// link that never carried a key. This flag is what tells the two apart, so
  /// that the recipient can be told the link itself is damaged instead of being
  /// left to guess why the key they were sent is not being used.
  final bool sharedFileKeyIsDamaged;

  /// Everything a v2 shared file link embedded, parsed.
  ///
  /// `null` for a v1 link - every link ArDrive produced before this schema -
  /// which the shared file page resolves over GraphQL exactly as it always
  /// has. A payload lets the page paint the file's details with no network
  /// round trip at all.
  ///
  /// The payload's own key ([SharedFileLinkPayload.key]) is the same key
  /// [sharedFileKey] and [sharedFileKeyIsDamaged] were derived from; those two
  /// stay authoritative so that v1 and v2 links present the key identically.
  final SharedFileLinkPayload? sharedFileLinkPayload;

  const AppRoutePath({
    this.signingIn = false,
    this.getStarted = false,
    this.driveId,
    this.driveName,
    this.driveFolderId,
    this.sharedDriveKey,
    this.sharedRawDriveKey,
    this.sharedFileId,
    this.sharedFileKey,
    this.sharedRawFileKey,
    this.sharedFileKeyIsDamaged = false,
    this.sharedFileLinkPayload,
  });

  /// Creates a route that lets the user sign in.
  factory AppRoutePath.signIn() => const AppRoutePath(signingIn: true);

  factory AppRoutePath.getStarted() => const AppRoutePath(getStarted: true);

  /// Creates a route that points to a particular drive.
  factory AppRoutePath.driveDetail({
    required String driveId,
    String? driveName,
    DriveKey? sharedDrivePk,
    String? sharedRawDriveKey,
  }) =>
      AppRoutePath(
        driveId: driveId,
        driveName: driveName,
        sharedDriveKey: sharedDrivePk,
        sharedRawDriveKey: sharedRawDriveKey,
      );

  /// Creates a route that points to a folder in a particular drive.
  factory AppRoutePath.folderDetail({
    required String driveId,
    required String driveFolderId,
  }) =>
      AppRoutePath(driveId: driveId, driveFolderId: driveFolderId);

  /// Creates a route that points to a particular shared file.
  factory AppRoutePath.sharedFile({
    required String sharedFileId,
    SecretKey? sharedFilePk,
    String? sharedRawFileKey,
    bool sharedFileKeyIsDamaged = false,
    SharedFileLinkPayload? linkPayload,
  }) =>
      AppRoutePath(
        sharedFileId: sharedFileId,
        sharedFileKey: sharedFilePk,
        sharedRawFileKey: sharedRawFileKey,
        sharedFileKeyIsDamaged: sharedFileKeyIsDamaged,
        sharedFileLinkPayload: linkPayload,
      );

  factory AppRoutePath.unknown() => const AppRoutePath();
}
