import 'package:ardrive/search/domain/bloc/search_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Says which drives a search could not look inside, and offers to sync them.
///
/// Shown with search results whenever some drives' files are not on this
/// device. Nothing is shown when every drive was searched: a note that only
/// says all is well is noise beside the results.
class SearchCoverageNotice extends StatelessWidget {
  const SearchCoverageNotice({super.key, this.compact = false});

  /// The dropdown's version: tighter, to sit above a short list.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      buildWhen: (previous, current) =>
          previous.query.isEmpty != current.query.isEmpty ||
          previous.coverage != current.coverage ||
          previous.syncStatus != current.syncStatus ||
          previous.failedSyncCount != current.failedSyncCount,
      builder: (context, state) {
        final coverage = state.coverage;

        // Before anything is searched there are no results to qualify, and
        // "Searched 2 of 6 drives" would be untrue.
        if (state.query.isEmpty || coverage.isComplete) {
          return const SizedBox.shrink();
        }

        final localizations = appLocalizationsOf(context);
        final typography = ArDriveTypographyNew.of(context);
        final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
        final unsearched = coverage.unsearchedDriveIds.length;
        final noneSearched = coverage.searchedDrives == 0;

        final lead = noneSearched
            ? localizations.searchCoverageNoneSynced(unsearched)
            : localizations.searchCoverageSearched(
                coverage.searchedDrives,
                coverage.totalDrives,
              );

        final status = switch (state.syncStatus) {
          SearchSyncStatus.none => noneSearched
              ? localizations.searchCoverageSyncThem(unsearched)
              : localizations.searchCoverageSyncOthers(unsearched),
          SearchSyncStatus.syncing => noneSearched
              ? localizations.searchCoverageSyncingThem(unsearched)
              : localizations.searchCoverageSyncing(unsearched),
          SearchSyncStatus.otherSyncRunning =>
            localizations.searchCoverageOtherSyncRunning,
          SearchSyncStatus.failed =>
            localizations.searchCoverageSyncFailed(state.failedSyncCount),
          SearchSyncStatus.refused => localizations.searchCoverageSyncRefused,
        };

        final syncing = state.syncStatus == SearchSyncStatus.syncing;
        final failed = state.syncStatus == SearchSyncStatus.failed;

        void sync() =>
            context.read<SearchBloc>().add(const SearchSyncRequested());

        return Semantics(
          // Read out when it changes, so a screen reader hears that a sync
          // started, finished or failed without leaving the field.
          liveRegion: true,
          child: Container(
            padding: EdgeInsets.all(compact ? 12 : 16),
            decoration: BoxDecoration(
              color:
                  ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
              borderRadius: BorderRadius.circular(cardDefaultBorderRadius),
              border: Border.all(
                color: failed ? colorTokens.strokeRed : colorTokens.strokeLow,
              ),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 12,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 360 : 520),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: syncing
                            ? SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorTokens.iconHigh,
                                ),
                              )
                            : failed
                                ? ArDriveIcons.triangle(
                                    size: 16,
                                    color: colorTokens.strokeRed,
                                  )
                                : ArDriveIcons.cloudSync(
                                    size: 16,
                                    color: colorTokens.iconHigh,
                                  ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '$lead $status',
                          style: (compact
                              ? typography.paragraphSmall
                              : typography.paragraphNormal)(
                            color: colorTokens.textHigh,
                            fontWeight: ArFontWeight.semiBold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!syncing)
                  ArDriveButtonNew(
                    text: failed
                        ? localizations.tryAgain
                        : localizations.searchSyncDrives(unsearched),
                    typography: typography,
                    variant: ButtonVariant.primary,
                    maxHeight: compact ? 32 : 36,
                    // Only one sync runs at a time; this one can start when
                    // the other ends.
                    isDisabled:
                        state.syncStatus == SearchSyncStatus.otherSyncRunning,
                    onPressed: sync,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
