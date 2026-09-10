import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

@immutable
class AppRoutePath {
  /// Whether or not the user is trying to sign in.
  final bool signingIn;

  final bool getStarted;

  /// Whether the app is showing the list of the user's drives - `/drives`.
  ///
  /// The landing route of a login that has no link to honour. It is separate
  /// from [driveId] rather than "driveId == null" because the two are not
  /// opposites: a drive can be selected in the sidebar while the list is what
  /// is on screen, and only this says which of them the address bar means.
  final bool drivesList;

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

  /// The transaction the generalized viewer was asked for - `/view/{txId}`.
  ///
  /// Always a validated 43 character Arweave id; the route does not match
  /// anything else, so nothing downstream has to re-check it.
  final String? rawTransactionId;

  /// `n` - the file name hint of a `/view/{txId}` link, validated by the same
  /// rules as the shared file schema's (§1.3).
  ///
  /// A hint, never a fact: the viewer prefers what the gateway reports.
  final String? rawTransactionName;

  /// `ct` - the content type hint of a `/view/{txId}` link.
  final String? rawTransactionContentType;

  const AppRoutePath({
    this.signingIn = false,
    this.getStarted = false,
    this.drivesList = false,
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
    this.rawTransactionId,
    this.rawTransactionName,
    this.rawTransactionContentType,
  });

  /// Creates a route that lets the user sign in.
  factory AppRoutePath.signIn() => const AppRoutePath(signingIn: true);

  factory AppRoutePath.getStarted() => const AppRoutePath(getStarted: true);

  /// Creates a route that points at the list of the user's drives.
  factory AppRoutePath.drivesList() => const AppRoutePath(drivesList: true);

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
  ///
  /// Carries the drive key for the same reason [driveDetail] does: a folder
  /// inside a private drive cannot be read without it, and a link that names
  /// one has nowhere else to put it.
  factory AppRoutePath.folderDetail({
    required String driveId,
    required String driveFolderId,
    String? driveName,
    DriveKey? sharedDrivePk,
    String? sharedRawDriveKey,
  }) =>
      AppRoutePath(
        driveId: driveId,
        driveFolderId: driveFolderId,
        driveName: driveName,
        sharedDriveKey: sharedDrivePk,
        sharedRawDriveKey: sharedRawDriveKey,
      );

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

  /// Creates a route that points at any Arweave transaction, ArDrive being the
  /// friendly front end - `docs/FILE_SHARING_REDESIGN_PLAN.md` §1.3, §4.3.
  factory AppRoutePath.rawTransaction({
    required String txId,
    String? name,
    String? contentType,
  }) =>
      AppRoutePath(
        rawTransactionId: txId,
        rawTransactionName: name,
        rawTransactionContentType: contentType,
      );

  factory AppRoutePath.unknown() => const AppRoutePath();
}
