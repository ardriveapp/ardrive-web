import 'package:ardrive/blocs/fs_entry_snapshots/fs_entry_snapshots_cubit.dart';
import 'package:ardrive/blocs/fs_entry_snapshots/models/snapshot_display_item.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/components/snapshots_tab/snapshot_list_item.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/utils/user_utils.dart';

/// Tab that displays all snapshots for a drive.
class SnapshotsTab extends StatelessWidget {
  final Drive drive;

  const SnapshotsTab({
    super.key,
    required this.drive,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FsEntrySnapshotsCubit, FsEntrySnapshotsState>(
      builder: (context, state) {
        if (state is FsEntrySnapshotsLoading ||
            state is FsEntrySnapshotsInitial) {
          return const Center(
            child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
          );
        }

        if (state is FsEntrySnapshotsFailure) {
          return _buildErrorState(context);
        }

        if (state is FsEntrySnapshotsSuccess) {
          if (state.snapshots.isEmpty) {
            return _buildEmptyState(context, state.shouldRecommendSnapshot);
          }
          return _buildSnapshotsList(
            context,
            state.snapshots,
            state.shouldRecommendSnapshot,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return ArDriveEmptyState(
      icon: ArDriveIcons.triangle(),
      title: appLocalizationsOf(context).errorLoadingSnapshots,
      actionLabel: appLocalizationsOf(context).tryAgain,
      onAction: () => context.read<FsEntrySnapshotsCubit>().refresh(),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool shouldRecommendSnapshot) {
    // Snapshots are signed by the drive owner's wallet, so nobody else is
    // offered one - a visitor least of all. A drive that would benefit gets
    // the main button; a small one only the quieter "anyway".
    final canCreate = _canCreateSnapshot(context);
    final strings = appLocalizationsOf(context);

    return ArDriveEmptyState(
      icon: ArDriveIcons.iconCreateSnapshot(),
      title: shouldRecommendSnapshot
          ? strings.snapshotRecommended
          : strings.noSnapshotsFound,
      message: shouldRecommendSnapshot
          ? strings.snapshotRecommendedBody
          : strings.snapshotsHelpSyncSpeed,
      actionLabel:
          canCreate && shouldRecommendSnapshot ? strings.createSnapshot : null,
      onAction: () => _launchCreateSnapshotDialog(context),
      secondaryActionLabel: canCreate && !shouldRecommendSnapshot
          ? strings.createSnapshotAnyway
          : null,
      onSecondaryAction: () => _launchCreateSnapshotDialog(context),
    );
  }

  Widget _buildSnapshotsList(
    BuildContext context,
    List<SnapshotDisplayItem> snapshots,
    bool shouldRecommendSnapshot,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      itemCount: snapshots.length + (shouldRecommendSnapshot ? 1 : 0),
      itemBuilder: (context, index) {
        // Show recommendation banner at the top if drive would benefit
        if (shouldRecommendSnapshot && index == 0) {
          return _buildRecommendationBanner(context);
        }

        final snapshotIndex = shouldRecommendSnapshot ? index - 1 : index;
        final snapshot = snapshots[snapshotIndex];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SnapshotListItem(
            snapshot: snapshot,
          ),
        );
      },
    );
  }

  /// Whether the reader can create a snapshot of this drive: its owner, with
  /// a wallet to sign it. False for everyone else, including a visitor.
  bool _canCreateSnapshot(BuildContext context) =>
      isDriveOwner(context.read<ArDriveAuth>(), drive.ownerAddress);

  Widget _buildRecommendationBanner(BuildContext context) {
    // The banner is a call to create one, so it has nothing to say to a
    // reader who cannot.
    if (!_canCreateSnapshot(context)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: ArDriveSpacing.md),
      child: ArDriveNotice(
        type: ArDriveNoticeType.info,
        title: appLocalizationsOf(context).snapshotRecommended,
        message: appLocalizationsOf(context).createNewSnapshotRecommendation,
        actionLabel: appLocalizationsOf(context).createSnapshot,
        onAction: () => _launchCreateSnapshotDialog(context),
      ),
    );
  }

  void _launchCreateSnapshotDialog(BuildContext context) {
    // promptToCreateSnapshot already dispatches DriveSnapshotting
    promptToCreateSnapshot(context, drive);
  }
}
