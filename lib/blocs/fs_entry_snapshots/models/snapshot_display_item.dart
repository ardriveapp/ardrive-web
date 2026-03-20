import 'package:ardrive/models/enums.dart';
import 'package:equatable/equatable.dart';

/// Represents a snapshot for display in the UI.
///
/// This model is used by [FsEntrySnapshotsCubit] to represent both
/// confirmed snapshots from the blockchain and pending snapshots
/// that are awaiting confirmation.
class SnapshotDisplayItem extends Equatable {
  /// The transaction ID of the snapshot on Arweave.
  final String txId;

  /// The drive ID this snapshot belongs to.
  final String driveId;

  /// The starting block height of the snapshot range.
  final int blockStart;

  /// The ending block height of the snapshot range.
  final int blockEnd;

  /// When this snapshot was created (from block timestamp for confirmed,
  /// current time for pending).
  final DateTime createdAt;

  /// The transaction status: 'pending', 'confirmed', or 'failed'.
  /// Uses [TransactionStatus] constants.
  final String status;

  const SnapshotDisplayItem({
    required this.txId,
    required this.driveId,
    required this.blockStart,
    required this.blockEnd,
    required this.createdAt,
    this.status = TransactionStatus.confirmed,
  });

  /// Whether this snapshot is pending confirmation on Arweave.
  bool get isPending => status == TransactionStatus.pending;

  /// Whether this snapshot has been confirmed on Arweave.
  bool get isConfirmed => status == TransactionStatus.confirmed;

  /// Whether this snapshot transaction failed.
  bool get isFailed => status == TransactionStatus.failed;

  /// Creates a copy of this item with the given fields replaced.
  SnapshotDisplayItem copyWith({
    String? txId,
    String? driveId,
    int? blockStart,
    int? blockEnd,
    DateTime? createdAt,
    String? status,
  }) {
    return SnapshotDisplayItem(
      txId: txId ?? this.txId,
      driveId: driveId ?? this.driveId,
      blockStart: blockStart ?? this.blockStart,
      blockEnd: blockEnd ?? this.blockEnd,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [
        txId,
        driveId,
        blockStart,
        blockEnd,
        createdAt,
        status,
      ];
}
