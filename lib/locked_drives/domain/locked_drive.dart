import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/locked_drives/domain/drive_fingerprint.dart';
import 'package:equatable/equatable.dart';

/// A private drive this wallet owns that the session can't open.
///
/// Deliberately not a `Drive` row. The drive's name and root folder are inside
/// its encrypted metadata, so a locked drive has neither, and a row with
/// placeholders for them is read as a real drive by everything that reads the
/// drives table: export, snapshots, search, the ghost fixer, the v1 drive
/// migration. Locked drives live only in [DriveUnlockSession], in memory, and
/// become a row the moment a key that opens them is found.
class LockedDrive extends Equatable {
  const LockedDrive({
    required this.driveId,
    required this.ownerAddress,
    required this.signatureType,
    required this.lastUpdated,
  });

  final String driveId;
  final String ownerAddress;

  /// From the drive's `Signature-Type` tag; a drive without one is v1.
  final DriveSignatureType signatureType;

  /// When the drive's newest metadata was written: the one date known without
  /// its key.
  final DateTime lastUpdated;

  /// The three emoji that identify this drive. See [driveFingerprint].
  String get fingerprint => driveFingerprint(driveId);

  @override
  List<Object?> get props =>
      [driveId, ownerAddress, signatureType, lastUpdated];
}
