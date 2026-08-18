part of 'drive_share_cubit.dart';

@immutable
abstract class DriveShareState extends Equatable {
  const DriveShareState();

  @override
  List<Object?> get props => [];
}

/// [DriveShareLoadInProgress] means that the drive share details are being loaded.
class DriveShareLoadInProgress extends DriveShareState {}

/// [DriveShareLoadSuccess] provides details for the user to share the drive with.
class DriveShareLoadSuccess extends DriveShareState {
  final Drive drive;

  /// The link to share access of this drive with.
  final Uri driveShareLink;

  /// Whether the link points at one folder rather than the whole drive.
  final bool isFolder;

  /// Whether the drive key is embedded in [driveShareLink].
  final bool keyIsInLink;

  /// The drive key, for the sharer to hand over separately.
  ///
  /// `null` for a public drive, which has none.
  final String? driveKeyBase64;

  const DriveShareLoadSuccess({
    required this.drive,
    required this.driveShareLink,
    this.isFolder = false,
    this.keyIsInLink = false,
    this.driveKeyBase64,
  });

  /// Whether the key travels as its own artifact rather than inside the link.
  bool get hasSeparateKeyArtifact => driveKeyBase64 != null && !keyIsInLink;

  @override
  List<Object?> get props => [
        drive,
        driveShareLink,
        isFolder,
        keyIsInLink,
        driveKeyBase64,
      ];

  /// Equatable stringifies [props] in debug builds, and one of them is a drive
  /// key. Same redaction, for the same reason, as [FileShareLoadSuccess].
  ///
  /// The link is printed whole: it is only a secret when the sharer embedded
  /// the key in it, and [keyIsInLink] says when that is.
  @override
  String toString() => 'DriveShareLoadSuccess(drive: ${drive.id}, '
      'isFolder: $isFolder, keyIsInLink: $keyIsInLink, '
      'driveKey: ${driveKeyBase64 == null ? 'none' : '<redacted>'})';
}

/// [DriveShareLoadFail] shows failiure states in the UI.
///
/// Carries no message: the dialog owns the copy so that it can be localized,
/// which a cubit with no [BuildContext] cannot do. This is the same shape the
/// file share dialog's failure states use.
class DriveShareLoadFail extends DriveShareState {
  const DriveShareLoadFail();
}
