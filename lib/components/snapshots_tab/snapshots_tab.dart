import 'package:ardrive/blocs/fs_entry_snapshots/fs_entry_snapshots_cubit.dart';
import 'package:ardrive/blocs/fs_entry_snapshots/models/snapshot_display_item.dart';
import 'package:ardrive/components/snapshots_tab/snapshot_list_item.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Tab that displays all snapshots for a drive.
class SnapshotsTab extends StatelessWidget {
  const SnapshotsTab({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FsEntrySnapshotsCubit, FsEntrySnapshotsState>(
      builder: (context, state) {
        if (state is FsEntrySnapshotsLoading ||
            state is FsEntrySnapshotsInitial) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (state is FsEntrySnapshotsFailure) {
          return _buildErrorState(context, state.errorMessage);
        }

        if (state is FsEntrySnapshotsSuccess) {
          if (state.snapshots.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildSnapshotsList(context, state.snapshots);
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildErrorState(BuildContext context, String? errorMessage) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArDriveIcons.triangle(
              size: 48,
              color: colorTokens.textLow,
            ),
            const SizedBox(height: 16),
            Text(
              appLocalizationsOf(context).errorLoadingSnapshots,
              style: typography.paragraphNormal(
                color: colorTokens.textLow,
                fontWeight: ArFontWeight.semiBold,
              ),
              textAlign: TextAlign.center,
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                errorMessage,
                style: typography.paragraphSmall(
                  color: colorTokens.textLow,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            ArDriveButton(
              text: appLocalizationsOf(context).tryAgain,
              style: ArDriveButtonStyle.secondary,
              onPressed: () {
                context.read<FsEntrySnapshotsCubit>().refresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArDriveIcons.iconCreateSnapshot(
              size: 48,
              color: colorTokens.textLow,
            ),
            const SizedBox(height: 16),
            Text(
              appLocalizationsOf(context).noSnapshotsFound,
              style: typography.paragraphNormal(
                color: colorTokens.textLow,
                fontWeight: ArFontWeight.semiBold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              appLocalizationsOf(context).snapshotsHelpSyncSpeed,
              style: typography.paragraphSmall(
                color: colorTokens.textLow,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotsList(
    BuildContext context,
    List<SnapshotDisplayItem> snapshots,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      itemCount: snapshots.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final snapshot = snapshots[index];
        return SnapshotListItem(
          snapshot: snapshot,
        );
      },
    );
  }
}
