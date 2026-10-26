import 'package:ardrive/arns/domain/undername_validation.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';

/// How long after a lease ends changes stay blocked until it is renewed
/// (`LEASE_GRACE_PERIOD` in `@ar.io/sdk`).
const arnsLeaseGracePeriod = Duration(days: 14);

/// The ArNS wallet's relationship to a name, from the ANT's owner. Decides
/// how a change is paid: an owner through Turbo with credits, a controller
/// with its own Solana fee (docs/NAMES.md, Q23).
enum ArNSRole { owner, controller }

/// The ArDrive item a record points to, when it is one.
sealed class ArNSTarget extends Equatable {
  const ArNSTarget({required this.driveId, required this.isLatestVersion});

  final String driveId;

  /// False when the name points at an older version, as it does after a new
  /// version is uploaded from an app that doesn't move names.
  final bool isLatestVersion;
}

/// A file, which covers deployments: a manifest is a file.
class ArNSFileItem extends ArNSTarget {
  const ArNSFileItem({
    required this.fileId,
    required super.driveId,
    required this.name,
    required this.parentFolderId,
    required this.isManifest,
    required this.isHidden,
    required super.isLatestVersion,
  });

  final String fileId;
  final String name;
  final String parentFolderId;
  final bool isManifest;
  final bool isHidden;

  @override
  List<Object?> get props => [
        fileId,
        driveId,
        name,
        parentFolderId,
        isManifest,
        isHidden,
        isLatestVersion,
      ];
}

class ArNSPublicationItem extends ArNSTarget {
  const ArNSPublicationItem({
    required this.publicationId,
    required super.driveId,
    required this.folderId,
    required super.isLatestVersion,
  });

  final String publicationId;

  /// The folder it shows, or null for the whole drive.
  final String? folderId;

  @override
  List<Object?> get props =>
      [publicationId, driveId, folderId, isLatestVersion];
}

/// One record of a name: the name itself (`@`) or an undername.
class ArNSNameRecord extends Equatable {
  const ArNSNameRecord({
    required this.name,
    required this.undername,
    required this.transactionId,
    required this.ttlSeconds,
    this.target,
  });

  final String name;
  final String undername;
  final String transactionId;
  final int ttlSeconds;

  /// Null when it points outside ArDrive, or at nothing ArDrive knows here:
  /// "Points elsewhere".
  final ArNSTarget? target;

  bool get isApex => undername == arnsApex;

  /// `blog_ardrive`, or `ardrive` for the name itself.
  String get literalName => literalArNSName(undername, name);

  ArNSNameRecord withTarget(ArNSTarget? target) => ArNSNameRecord(
        name: name,
        undername: undername,
        transactionId: transactionId,
        ttlSeconds: ttlSeconds,
        target: target,
      );

  @override
  List<Object?> get props =>
      [name, undername, transactionId, ttlSeconds, target];
}

/// What a record points to, as every screen that shows it says it: the Names
/// page, the name picker and the details panel.
enum ArNSPointsToKind {
  /// The placeholder: "Nothing published here".
  nothingPublished,

  /// The latest version of a file or deployment.
  file,

  /// An older version of a file or deployment.
  olderVersion,

  publication,

  /// Outside ArDrive, or nothing ArDrive knows here: "Points elsewhere".
  elsewhere,
}

/// The one classification of [record], so no two screens disagree.
ArNSPointsToKind arnsPointsToKind(
  ArNSNameRecord record, {
  String? placeholder,
}) {
  if (placeholder != null && record.transactionId == placeholder) {
    return ArNSPointsToKind.nothingPublished;
  }
  return switch (record.target) {
    ArNSFileItem(:final isLatestVersion) =>
      isLatestVersion ? ArNSPointsToKind.file : ArNSPointsToKind.olderVersion,
    ArNSPublicationItem() => ArNSPointsToKind.publication,
    null => ArNSPointsToKind.elsewhere,
  };
}

/// A name the ArNS wallet owns or manages, with its records.
class ArNSManagedName extends Equatable {
  const ArNSManagedName({
    required this.name,
    required this.processId,
    required this.role,
    required this.type,
    required this.endTimestamp,
    required this.undernameLimit,
    required this.records,
  });

  final String name;
  final String processId;
  final ArNSRole role;
  final ArNSNameType type;

  /// When a lease ends; null for a permanent name.
  final DateTime? endTimestamp;
  final int undernameLimit;

  /// `@` first, then undernames by name.
  final List<ArNSNameRecord> records;

  ArNSNameRecord? get apex {
    for (final record in records) {
      if (record.isApex) return record;
    }
    return null;
  }

  int get undernamesUsed => records.where((r) => !r.isApex).length;

  bool get hasFreeUndername => undernamesUsed < undernameLimit;

  /// In the grace period after a lease ended: the chain rejects changes.
  bool isInGracePeriod(DateTime now) {
    final end = endTimestamp;
    return end != null &&
        !now.isBefore(end) &&
        now.isBefore(end.add(arnsLeaseGracePeriod));
  }

  /// Gone past its grace period: no longer the wallet's.
  bool isExpired(DateTime now) {
    final end = endTimestamp;
    return end != null && !now.isBefore(end.add(arnsLeaseGracePeriod));
  }

  ArNSManagedName withRecords(List<ArNSNameRecord> records) => ArNSManagedName(
        name: name,
        processId: processId,
        role: role,
        type: type,
        endTimestamp: endTimestamp,
        undernameLimit: undernameLimit,
        records: records,
      );

  @override
  List<Object?> get props => [
        name,
        processId,
        role,
        type,
        endTimestamp,
        undernameLimit,
        records,
      ];
}
