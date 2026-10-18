import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/file_download_dialog.dart';
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
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

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

  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  return showModalBottomSheet(
    isScrollControlled: true,
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: colorTokens.containerL2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6.0),
          topRight: Radius.circular(6.0),
        ),
      ),
      child: Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: BlocProvider.value(
          value: context.read<DriveDetailCubit>(),
          child: FileSearchModal(
            driveDetailCubit: context.read<DriveDetailCubit>(),
            drivesCubit: drivesCubit,
            onNavigateToFolder: onNavigateToFolder,
          ),
        ),
      ),
    ),
  );
}

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
  });

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
    return ScreenTypeLayout.builder(mobile: (context) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: colorTokens.containerRed,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
            ),
            height: 6,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildSearchHeader(typography, colorTokens),
                  const SizedBox(height: 16),
                  _buildSearchField(),
                  const SizedBox(height: 16),
                  const SearchCoverageNotice(),
                  _buildSearchResults(context, typography, colorTokens),
                ],
              ),
            ),
          ),
        ],
      );
    }, desktop: (context) {
      return ArDriveLoginModal(
        width: MediaQuery.of(context).size.width * 0.6,
        content: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSearchHeader(typography, colorTokens),
              const SizedBox(height: 16),
              _buildSearchField(),
              const SizedBox(height: 16),
              const SearchCoverageNotice(),
              _buildSearchResults(context, typography, colorTokens),
            ],
          ),
        ),
      );
    });
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

  Widget _buildSearchHeader(
    ArdriveTypographyNew typography,
    ArDriveColorTokens colorTokens,
  ) {
    return Text(
      'Search for a file, folder, or drive',
      style: typography.heading4(
          color: colorTokens.textHigh, fontWeight: ArFontWeight.bold),
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
                    typography,
                    colorTokens,
                  ),
                ),
              ),
            );
          } else if (state.status == SearchStatus.idle) {
            return Center(
              child: Text(
                'Nothing here yet! Start by searching for a file name, folder, or drive above.',
                style: typography.paragraphXLarge(
                  color: colorTokens.textHigh,
                  fontWeight: ArFontWeight.semiBold,
                ),
                textAlign: TextAlign.center,
              ),
            );
          } else if (state.status == SearchStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: Text(
              'We couldn\'t find any files, folders, or drives matching your search. Please check your spelling or try searching with a different keyword.',
              style: typography.paragraphXLarge(
                fontWeight: ArFontWeight.semiBold,
                color: colorTokens.textHigh,
              ),
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResultItem(
    BuildContext context,
    SearchResult searchResult,
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
          title: Wrap(
            children: [
              Text(
                name,
                style: typography.paragraphXLarge(
                  color: colorTokens.textHigh,
                  fontWeight: ArFontWeight.bold,
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
          subtitle: _buildSubtitle(searchResult, typography, colorTokens),
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
            message: 'This file has an ArNS name',
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

  Widget _buildSubtitle(
    SearchResult searchResult,
    ArdriveTypographyNew typography,
    ArDriveColorTokens colorTokens,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Drive: ${searchResult.drive.name}',
          style: typography.paragraphNormal(
            color: colorTokens.textLow,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
        if (searchResult.parentFolder != null)
          Text(
            'Folder: ${searchResult.parentFolder!.name}',
            style: typography.paragraphNormal(
              color: colorTokens.textLow,
              fontWeight: ArFontWeight.semiBold,
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
