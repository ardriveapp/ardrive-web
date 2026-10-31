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

  return showArDriveBottomSheet(
    context,
    builder: (_) => ArDriveBottomSheet(
      title: _searchTitle(context),
      closeLabel: appLocalizationsOf(context).close,
      fillsHeight: true,
      content: BlocProvider.value(
        value: driveDetailCubit,
        child: FileSearchModal(
          driveDetailCubit: driveDetailCubit,
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

  return showArDriveDialog(
    context,
    content: FileSearchModal(
      driveDetailCubit: driveDetailCubit,
      drivesCubit: drivesCubit,
      onNavigateToFolder: onNavigateToFolder,
    ),
    // The standard scrim: a light wash lit the page up behind the dialog
    // instead of dimming it.
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
  /// the standard dialog. Set by how it was opened; when the window is
  /// resized across the phone layout's breakpoint it reopens in the other
  /// form (see [_FileSearchModalState.didChangeDependencies]).
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
  bool _reopening = false;

  /// The form the app's layout shows search in at this width: the sheet with
  /// the phone layout's search icon, the dialog with the desktop search box.
  bool _wantsSheet() =>
      getDeviceType(MediaQuery.sizeOf(context)) != DeviceScreenType.desktop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resized across the breakpoint: a dialog on a phone layout, or a sheet
    // on a desktop one, is the wrong surface. Reopen in the right one; the
    // session keeps the query, so nothing typed is lost. Only while search is
    // the top route: a dialog it opened (a download) may sit on it, and pop
    // would close that instead. Reading the route's status here makes this
    // run again when that dialog closes.
    final onTop = ModalRoute.of(context)?.isCurrent ?? false;
    if (!_reopening && onTop && _wantsSheet() != widget.inSheet) {
      _reopening = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reopen());
    }
  }

  void _reopen() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      _reopening = false;
      return;
    }
    final navigator = Navigator.of(context);
    final host = navigator.context;
    final reopen =
        widget.inSheet ? showSearchModalDesktop : showSearchModalBottomSheet;
    navigator.pop();
    reopen(
      context: host,
      driveDetailCubit: widget.driveDetailCubit,
      drivesCubit: widget.drivesCubit,
      onNavigateToFolder: widget.onNavigateToFolder,
    );
  }

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
          if (state.status == SearchStatus.failed) {
            // Not the no-matches state, which suggests checking the spelling:
            // the search itself failed.
            final strings = appLocalizationsOf(context);
            return Padding(
              padding: const EdgeInsets.only(top: ArDriveSpacing.md),
              child: Align(
                alignment: Alignment.topCenter,
                child: ArDriveNotice(
                  key: const Key('searchFailedNotice'),
                  type: ArDriveNoticeType.error,
                  message: strings.searchFailed,
                  actionLabel: strings.tryAgain,
                  onAction: _session.submit,
                ),
              ),
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
                    fontWeight: ArFontWeight.semiBold,
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
