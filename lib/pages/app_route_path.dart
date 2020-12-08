import 'package:meta/meta.dart';

@immutable
class AppRoutePath {
  final String driveId;
  final String driveFolderId;

  final String sharedFileId;

  AppRoutePath({this.driveId, this.driveFolderId, this.sharedFileId});

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
  factory AppRoutePath.sharedFile({@required String sharedFileId}) =>
      AppRoutePath(sharedFileId: sharedFileId);

  factory AppRoutePath.unknown() => AppRoutePath();
}
