import 'package:equatable/equatable.dart';

/// One row of the drives list: everything the page knows about a drive,
/// resolved once so the widget only has to draw.
///
/// Every field is either a fact or explicitly absent. There is no field here
/// whose zero doubles as "we do not know" - that distinction is what
/// [hasBeenWalked] carries, and it is why [fileCount] and [totalSize] are
/// nullable rather than defaulted.
class DriveListItem extends Equatable {
  const DriveListItem({
    required this.id,
    required this.name,
    required this.isPrivate,
    required this.isSharedWithMe,
    required this.dateCreated,
    required this.hasBeenWalked,
    required this.fileCount,
    required this.totalSize,
    required this.lastSyncedAt,
    required this.isSyncing,
  });

  final String id;
  final String name;

  /// Public or private. Drawn as a marker rather than a column: it is the one
  /// property of a drive that changes what the user may do with it.
  final bool isPrivate;

  /// A drive owned by somebody else and attached by this user.
  ///
  /// Marked in place rather than split into a second list. Two sections put
  /// the smaller group below the fold, and the smaller group here is the one
  /// with the surprising behaviour.
  final bool isSharedWithMe;

  final DateTime dateCreated;

  /// Whether this drive's history has actually been read on this device.
  ///
  /// The local tables answer instantly and answer zero for a drive nothing has
  /// looked at, which is indistinguishable from an empty drive. This is the
  /// flag that tells the two apart, and everything derived from row counts is
  /// withheld when it is false.
  final bool hasBeenWalked;

  /// Files stored locally for this drive, or null when the drive has never
  /// been walked and the number would therefore be a guess dressed as a count.
  ///
  /// Files, not items: a sync counts folders as items too, and one word over
  /// two different numbers on one page is what this name used to be.
  final int? fileCount;

  /// The sum of those files' sizes in bytes, on the same terms as [fileCount].
  final int? totalSize;

  /// When this device last finished a sync covering this drive.
  ///
  /// Null has two meanings, separated by [hasBeenWalked]: never synced at all,
  /// or synced by a build that did not yet write this down. The row says
  /// "Never synced" for the first and a bare "Synced" for the second, because
  /// claiming a time we do not have is the failure this whole series is about.
  final DateTime? lastSyncedAt;

  /// Whether a sync covering this drive is running right now.
  final bool isSyncing;

  @override
  List<Object?> get props => [
        id,
        name,
        isPrivate,
        isSharedWithMe,
        dateCreated,
        hasBeenWalked,
        fileCount,
        totalSize,
        lastSyncedAt,
        isSyncing,
      ];
}
