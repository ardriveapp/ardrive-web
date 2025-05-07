import 'package:ardrive/core/crypto/crypto.dart';
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
  }) =>
      AppRoutePath(
        sharedFileId: sharedFileId,
        sharedFileKey: sharedFilePk,
        sharedRawFileKey: sharedRawFileKey,
      );

  factory AppRoutePath.unknown() => const AppRoutePath();
}
