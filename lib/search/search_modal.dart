import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/file_download_dialog.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/search/domain/bloc/search_bloc.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/search_coverage_notice.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/search/search_result_navigator.dart';
import 'package:ardrive/search/search_result_view.dart';
import 'package:ardrive/search/search_scope.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/models.dart';

/// The search for the session, full screen on a phone. It searches the
/// session's query (see [SearchSession]), so it opens on whatever was last
/// typed.
Future<void> showSearchModalBottomSheet({
  required BuildContext context,
  required DriveDetailCubit driveDetailCubit,
  required DrivesCubit drivesCubit,

  /// See [SearchResultNavigator.onNavigateToFolder].
  void Function(String driveId, String folderId, {String? itemId})?
      onNavigateToFolder,
}) {
  PlausibleEventTracker.trackPageview(page: PlausiblePageView.searchPage);

  return showArDriveBottomSheet(
    context,
    builder: (_) => ArDriveBottomSheet(
      title: _searchTitle(context),
      fillsHeight: true,
      content: BlocProvider.value(
        value: context.read<DriveDetailCubit>(),
        child: FileSearchModal(
          driveDetailCubit: context.read<DriveDetailCubit>(),
          drivesCubit: drivesCubit,
          onNavigateToFolder: onNavigateToFolder,
          inSheet: true,
        ),
      ),
    ),
  );
}

String _searchTitle(BuildContext context) => PublicationMode.isOn
    ? appLocalizationsOf(context).publicationSearchTitle
    : appLocalizationsOf(context).searchTitle;

/// Every result for the session's query, in a dialog. Opened from the search
/// box with Enter or "See all results".
Future<void> showSearchModalDesktop({
  required BuildContext context,
  required DriveDetailCubit driveDetailCubit,
  required DrivesCubit drivesCubit,

  /// See [SearchResultNavigator.onNavigateToFolder].
  void Function(String driveId, String folderId, {String? itemId})?
      onNavigateToFolder,
}) {
  PlausibleEventTracker.trackPageview(page: PlausiblePageView.searchPage);

  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return showArDriveDialog(
    context,
    content: FileSearchModal(
      driveDetailCubit: context.read<DriveDetailCubit>(),
      drivesCubit: drivesCubit,
      onNavigateToFolder: onNavigateToFolder,
    ),
    barrierColor: colorTokens.containerL1.withOpacity(0.8),
  );
}

class FileSearchModal extends StatefulWidget {
  const FileSearchModal({
    super.key,
    required this.driveDetailCubit,
    required this.drivesCubit,
    this.onNavigateToFolder,
    this.inSheet = false,
  });

  /// Whether a bottom sheet holds it, which gives the title. Otherwise it is
  /// the standard dialog. Set by how it was opened rather than read from the
  /// screen's width, so a window resized while it is open can't leave it
  /// without a surface.
  final bool inSheet;

  final DriveDetailCubit driveDetailCubit;
  final DrivesCubit drivesCubit;

  /// See [SearchResultNavigator.onNavigateToFolder].
  final void Function(String driveId, String folderId, {String? itemId})?
      onNavigateToFolder;

  @override
  State<FileSearchModal> createState() => _FileSearchModalState();
}

class _FileSearchModalState extends State<FileSearchModal> {
  late final SearchSession _session;

  @override
  void initState() {
    super.initState();

    _session = context.read<SearchSession>();

    // Results for what is already typed, now: opening on "Nothing here yet"
    // and filling in after the typing pause read as a search that had failed.
    if (_session.query.isNotEmpty) {
      _session.submit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final body = [
      _buildSearchField(),
      const SizedBox(height: ArDriveSpacing.md),
      const SearchCoverageNotice(),
      _buildSearchResults(context, typography, colorTokens),
    ];

    if (widget.inSheet) {
      return Column(children: body);
    }

    return ArDriveStandardModalNew(
      title: _searchTitle(context),
      hasCloseButton: true,
      width: MediaQuery.sizeOf(context).width * 0.6,
      content: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(children: body),
      ),
    );
  }

  Widget _buildSearchField() {
    return SearchTextField(
      controller: _session.controller,
      // Opened to search, so ready to type into.
      autofocus: true,
      onEditingComplete: () {},
      onFieldSubmitted: (_) => _session.submit(),
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    ArdriveTypographyNew typography,
    ArDriveColorTokens colorTokens,
  ) {
    final scrollController = ScrollController();
    return Expanded(
      child: BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) {
          // A newer query that is still loading keeps the last results up
          // rather than blanking the list.
          if (state.results.isNotEmpty && state.status != SearchStatus.empty) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ArDriveScrollBar(
                controller: scrollController,
                alwaysVisible: true,
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: state.results.length,
                  itemBuilder: (_, index) => _buildSearchResultItem(
                    context,
                    state.results[index],
                    state.query,
                    typography,
                    colorTokens,
                  ),
                ),
              ),
            );
          } else if (state.status == SearchStatus.idle) {
            final strings = appLocalizationsOf(context);
            return SingleChildScrollView(
              child: ArDriveEmptyState(
                icon: Icon(Icons.search, size: 32, color: colorTokens.iconLow),
                title: PublicationMode.isOn
                    ? strings.publicationSearchStart
                    : strings.searchStartTitle,
                message:
                    PublicationMode.isOn ? null : strings.searchStartMessage,
              ),
            );
          } else if (state.status == SearchStatus.loading) {
            return const Center(
              child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
            );
          }
          final strings = appLocalizationsOf(context);
          return SingleChildScrollView(
            child: ArDriveEmptyState(
              icon: Icon(Icons.search, size: 32, color: colorTokens.iconLow),
              title: PublicationMode.isOn
                  ? strings.publicationSearchNoMatches(state.query)
                  : strings.searchNoMatches(state.query),
              message: strings.searchNoMatchesHint,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResultItem(
    BuildContext context,
    SearchResult searchResult,
    String query,
    ArdriveTypographyNew typography,
    ArDriveColorTokens colorTokens,
  ) {
    final name = searchResultName(searchResult);
    final isHidden = searchResultIsHidden(searchResult);
    final leadingIcon = searchResultIcon(searchResult, colorTokens);
    final trailingIcons = _getTrailingIcons(context, searchResult, colorTokens);

    return HoverWidget(
      hoverScale: 1,
      child: ArDriveClickArea(
        child: ListTile(
          onTap: () => _handleNavigation(context, searchResult),
          leading: leadingIcon,
          title: Row(
            children: [
              Flexible(
                child: SearchMatchText(
                  text: name,
                  query: query,
                  style: typography.paragraphXLarge(
                    color: colorTokens.textMid,
                    fontWeight: ArFontWeight.book,
                  ),
                  matchStyle: typography.paragraphXLarge(
                    color: colorTokens.textHigh,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
              ),
              if (isHidden)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ArDriveIcons.eyeClosed(
                    size: 20,
                  ),
                ),
            ],
          ),
          trailing: trailingIcons,
          subtitle: Text(
            searchResultLocation(context, searchResult),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typography.paragraphNormal(
              color: colorTokens.textLow,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _getTrailingIcons(
    BuildContext context,
    SearchResult searchResult,
    ArDriveColorTokens colorTokens,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (searchResult.hasArNSName ?? false)
          ArDriveTooltip(
            message: appLocalizationsOf(context).searchHasArnsName,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ArDriveIcons.arnsName(color: colorTokens.iconHigh),
            ),
          ),
        ArDriveIconButton(
          icon: ArDriveIcons.arrowRightOutline(color: colorTokens.iconHigh),
          onPressed: () => _handleNavigation(context, searchResult),
        ),
        const SizedBox(width: 8),
        if (searchResult.result is FileEntry)
          ArDriveIconButton(
            icon: ArDriveIcons.download(color: colorTokens.iconHigh),
            onPressed: () => promptToDownloadProfileFile(
              context: context,
              file: DriveDataTableItemMapper.fromFileEntryForSearchModal(
                searchResult.result as FileEntry,
              ),
            ),
          ),
      ],
    );
  }

  void _handleNavigation(BuildContext context, SearchResult searchResult) {
    final navigator = SearchResultNavigator(
      drivesCubit: widget.drivesCubit,
      driveDetailCubit: widget.driveDetailCubit,
      onNavigateToFolder: widget.onNavigateToFolder,
    );

    // Closed first: the navigator holds what it needs, and the page under the
    // dialog may be rebuilt as it goes.
    Navigator.of(context).pop();
    _session.clear();
    navigator.open(searchResult);
  }
}
