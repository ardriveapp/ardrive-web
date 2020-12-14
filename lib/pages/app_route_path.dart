import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';

@immutable
class AppRoutePath {
  final String driveId;
  final String driveFolderId;

  final String sharedFileId;

  /// The private key of the corresponding shared file.
  final SecretKey sharedFileKey;

  /// The private key of the corresponding shared file, encoded as Base64.
  final String sharedRawFileKey;

  AppRoutePath({
    this.driveId,
    this.driveFolderId,
    this.sharedFileId,
    this.sharedFileKey,
    this.sharedRawFileKey,
  });

  /// Creates a route that points to a particular drive.
  factory AppRoutePath.driveDetail({@required String driveId}) =>
      AppRoutePath(driveId: driveId);

  /// Creates a route that points to a folder in a particular drive.
  factory AppRoutePath.folderDetail({
    @required String driveId,
    @required String driveFolderId,
  }) =>
      AppRoutePath(driveId: driveId, driveFolderId: driveFolderId);

  /// Creates a route that points to a particular shared file.
  factory AppRoutePath.sharedFile({
    @required String sharedFileId,
    SecretKey sharedFilePk,
    String sharedRawFileKey,
  }) =>
      AppRoutePath(
        sharedFileId: sharedFileId,
        sharedFileKey: sharedFilePk,
        sharedRawFileKey: sharedRawFileKey,
      );

  factory AppRoutePath.unknown() => AppRoutePath();
}
