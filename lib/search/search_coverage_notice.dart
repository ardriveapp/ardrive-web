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

  /// The dropdown's version: one line across the top of the list, with the
  /// action as a link rather than a button. A boxed note with a red button
  /// sat above the results and took the eye before they did.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      buildWhen: (previous, current) =>
          previous.query.isEmpty != current.query.isEmpty ||
          previous.coverage != current.coverage ||
          previous.syncStatus != current.syncStatus ||
          previous.syncCount != current.syncCount,
      builder: (context, state) {
        final coverage = state.coverage;

        // Before anything is searched there are no results to qualify, and
        // "Searched 2 of 6 drives" would be untrue.
        if (state.query.isEmpty || coverage.isComplete) {
          return const SizedBox.shrink();
        }

        final localizations = appLocalizationsOf(context);
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
          // A sync that covers only some of them, such as one started from a
          // drive's own page, says how many rather than claiming all.
          SearchSyncStatus.syncing => state.syncCount < unsearched
              ? localizations.searchCoverageSyncingSome(state.syncCount)
              : noneSearched
                  ? localizations.searchCoverageSyncingThem(unsearched)
                  : localizations.searchCoverageSyncing(unsearched),
          SearchSyncStatus.otherSyncRunning =>
            localizations.searchCoverageOtherSyncRunning(unsearched),
          SearchSyncStatus.failed =>
            localizations.searchCoverageSyncFailed(state.syncCount),
          SearchSyncStatus.refused => localizations.searchCoverageSyncRefused,
        };

        final syncing = state.syncStatus == SearchSyncStatus.syncing;
        final failed = state.syncStatus == SearchSyncStatus.failed;

        void sync() =>
            context.read<SearchBloc>().add(const SearchSyncRequested());

        // 16, the spinner's size in a row (README, Loaders), and the icons
        // match it so the line doesn't shift as the state changes.
        final icon = syncing
            ? SizedBox.square(
                dimension: 16,
                child: ArDriveSpinner(color: colorTokens.iconHigh),
              )
            : failed
                ? ArDriveIcons.triangle(
                    size: 16,
                    color: colorTokens.statusErrorFg,
                  )
                : ArDriveIcons.cloudSync(
                    size: 16,
                    color: colorTokens.iconHigh,
                  );

        if (compact) {
          // The sentence that offers to sync is the link's own words here.
          final (String? sentence, String? link) = switch (state.syncStatus) {
            SearchSyncStatus.none => (
                null,
                noneSearched
                    ? localizations.searchSyncDrives(unsearched)
                    : localizations.searchCoverageSyncOthersLink(unsearched),
              ),
            SearchSyncStatus.syncing || SearchSyncStatus.otherSyncRunning => (
                status,
                null
              ),
            SearchSyncStatus.failed => (
                status,
                localizations.searchCoverageTryAgain,
              ),
            SearchSyncStatus.refused => (
                localizations.searchCoverageSyncNotStarted,
                localizations.searchCoverageTryAgain,
              ),
          };

          return Semantics(
            liveRegion: true,
            child: _CompactNotice(
              icon: icon,
              text: sentence == null ? lead : '$lead $sentence',
              link: link,
              onLink: sync,
            ),
          );
        }

        // The app's system notice: info, or error once a sync has failed. Its
        // action is the notice's own quiet button, reachable by Tab, never a
        // red primary - the drives page's split button is the one sync control
        // that gets weight. While the drives sync, a spinner stands where the
        // icon is and there is nothing to press.
        return Semantics(
          // Read out when it changes, so a screen reader hears that a sync
          // started, finished or failed without leaving the field.
          liveRegion: true,
          child: ArDriveNotice(
            type: failed ? ArDriveNoticeType.error : ArDriveNoticeType.info,
            message: '$lead $status',
            leading: syncing
                ? ArDriveSpinner(color: colorTokens.statusInfoFg)
                : null,
            actionLabel: syncing
                ? null
                : failed
                    ? localizations.tryAgain
                    : localizations.searchSyncDrives(unsearched),
            // Only one sync runs at a time; this one can start when the other
            // ends, so the action is shown but cannot be pressed.
            onAction: state.syncStatus == SearchSyncStatus.otherSyncRunning
                ? null
                : sync,
          ),
        );
      },
    );
  }
}

/// The note as one strip across the top of the dropdown: what was searched,
/// then the action, inline.
class _CompactNotice extends StatelessWidget {
  const _CompactNotice({
    required this.icon,
    required this.text,
    required this.link,
    required this.onLink,
  });

  final Widget icon;
  final String text;
  final String? link;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final style = typography.paragraphSmall(
      color: colorTokens.textMid,
      fontWeight: ArFontWeight.book,
    );
    final link = this.link;

    return ColoredBox(
      color: ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: icon),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: style,
                  children: [
                    TextSpan(text: text),
                    if (link != null) ...[
                      const TextSpan(text: ' '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: _NoticeLink(
                          label: link,
                          style: style,
                          onTap: onLink,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A link that acts without taking focus from the search field, so the
/// dropdown it sits in stays open. A keyboard reaches the same action as a
/// button in the search dialog, which Enter opens.
///
/// Announced as a button: it starts a sync rather than going anywhere
/// (README, Links).
class _NoticeLink extends StatelessWidget {
  const _NoticeLink({
    required this.label,
    required this.style,
    required this.onTap,
  });

  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(
            label,
            style: style.copyWith(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.semiBold.weight,
              decoration: TextDecoration.underline,
              decorationColor: colorTokens.textHigh,
            ),
          ),
        ),
      ),
    );
  }
}
