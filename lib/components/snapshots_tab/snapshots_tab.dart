import 'package:ardrive/blocs/fs_entry_snapshots/fs_entry_snapshots_cubit.dart';
import 'package:ardrive/blocs/fs_entry_snapshots/models/snapshot_display_item.dart';
import 'package:ardrive/components/create_snapshot_dialog.dart';
import 'package:ardrive/components/snapshots_tab/snapshot_list_item.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
            child: CircularProgressIndicator(),
          );
        }

        if (state is FsEntrySnapshotsFailure) {
          return _buildErrorState(context, state.errorMessage);
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

  Widget _buildEmptyState(BuildContext context, bool shouldRecommendSnapshot) {
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
              color: shouldRecommendSnapshot
                  ? colorTokens.textHigh
                  : colorTokens.textLow,
            ),
            const SizedBox(height: 16),
            Text(
              shouldRecommendSnapshot
                  ? appLocalizationsOf(context).snapshotRecommended
                  : appLocalizationsOf(context).noSnapshotsFound,
              style: typography.paragraphNormal(
                color: shouldRecommendSnapshot
                    ? colorTokens.textHigh
                    : colorTokens.textLow,
                fontWeight: ArFontWeight.semiBold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              shouldRecommendSnapshot
                  ? appLocalizationsOf(context).snapshotRecommendedBody
                  : appLocalizationsOf(context).snapshotsHelpSyncSpeed,
              style: typography.paragraphSmall(
                color: colorTokens.textLow,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (shouldRecommendSnapshot)
              ArDriveButton(
                text: appLocalizationsOf(context).createSnapshot,
                onPressed: () => _launchCreateSnapshotDialog(context),
              )
            else
              // Subtle link for small drives
              GestureDetector(
                onTap: () => _launchCreateSnapshotDialog(context),
                child: Text(
                  appLocalizationsOf(context).createSnapshotAnyway,
                  style: typography.paragraphSmall(
                    color: colorTokens.textLow,
                  ).copyWith(
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
          ],
        ),
      ),
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

        final snapshotIndex =
            shouldRecommendSnapshot ? index - 1 : index;
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

  Widget _buildRecommendationBanner(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorTokens.containerL2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorTokens.strokeMid,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Use vertical layout on narrow screens (mobile)
            final isNarrow = constraints.maxWidth < 400;

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: ArDriveIcons.info(
                          size: 20,
                          color: colorTokens.textMid,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appLocalizationsOf(context).snapshotRecommended,
                              style: typography.paragraphSmall(
                                fontWeight: ArFontWeight.semiBold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              appLocalizationsOf(context)
                                  .createNewSnapshotRecommendation,
                              style: typography.paragraphSmall(
                                color: colorTokens.textLow,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ArDriveButton(
                      text: appLocalizationsOf(context).createSnapshot,
                      style: ArDriveButtonStyle.secondary,
                      maxHeight: 36,
                      fontStyle: typography.paragraphSmall(
                        fontWeight: ArFontWeight.semiBold,
                      ),
                      onPressed: () => _launchCreateSnapshotDialog(context),
                    ),
                  ),
                ],
              );
            }

            // Desktop/wide layout
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ArDriveIcons.info(
                  size: 20,
                  color: colorTokens.textMid,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appLocalizationsOf(context).snapshotRecommended,
                        style: typography.paragraphSmall(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        appLocalizationsOf(context)
                            .createNewSnapshotRecommendation,
                        style: typography.paragraphSmall(
                          color: colorTokens.textLow,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ArDriveButton(
                  text: appLocalizationsOf(context).createSnapshot,
                  style: ArDriveButtonStyle.secondary,
                  maxHeight: 36,
                  fontStyle: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                  onPressed: () => _launchCreateSnapshotDialog(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _launchCreateSnapshotDialog(BuildContext context) {
    // promptToCreateSnapshot already dispatches DriveSnapshotting
    promptToCreateSnapshot(context, drive);
  }
}
