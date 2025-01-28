import 'dart:async';

import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/file_download_dialog.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/search/domain/bloc/search_bloc.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../models/models.dart';

Future<void> showSearchModalBottomSheet({
  required BuildContext context,
  required DriveDetailCubit driveDetailCubit,
  required DrivesCubit drivesCubit,
  required TextEditingController controller,
  String? query,
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
            initialQuery: query,
            driveDetailCubit: context.read<DriveDetailCubit>(),
            controller: controller,
            drivesCubit: drivesCubit,
          ),
        ),
      ),
    ),
  );
}

Future<void> showSearchModalDesktop({
  required BuildContext context,
  required DriveDetailCubit driveDetailCubit,
  required DrivesCubit drivesCubit,
  required TextEditingController controller,
  String? query,
}) {
  PlausibleEventTracker.trackPageview(page: PlausiblePageView.searchPage);

  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

  return showArDriveDialog(
    context,
    content: FileSearchModal(
      initialQuery: query,
      driveDetailCubit: context.read<DriveDetailCubit>(),
      controller: controller,
      drivesCubit: drivesCubit,
    ),
    barrierColor: colorTokens.containerL1.withOpacity(0.8),
  );
}

class FileSearchModal extends StatelessWidget {
  const FileSearchModal({
    super.key,
    required this.driveDetailCubit,
    required this.drivesCubit,
    this.initialQuery,
    required this.controller,
  });

  final DriveDetailCubit driveDetailCubit;
  final DrivesCubit drivesCubit;
  final String? initialQuery;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        RepositoryProvider<ArDriveSearchRepository>(
          create: (_) => ArDriveSearchRepository(
            context.read<DriveDao>(),
            ARNSDao(context.read<Database>()),
            context.read<FileRepository>(),
            context.read<FolderRepository>(),
          ),
        ),
        BlocProvider<SearchBloc>(
          create: (context) =>
              SearchBloc(context.read<ArDriveSearchRepository>())
                ..add(SearchQueryChanged(initialQuery ?? '')),
        ),
      ],
      child: _FileSearchModal(
        driveDetailCubit: driveDetailCubit,
        initialQuery: initialQuery,
        controller: controller,
        drivesCubit: drivesCubit,
      ),
    );
  }
}

class _FileSearchModal extends StatefulWidget {
  const _FileSearchModal({
    required this.driveDetailCubit,
    required this.drivesCubit,
    this.initialQuery,
    required this.controller,
  });

  final String? initialQuery;
  final DriveDetailCubit driveDetailCubit;
  final DrivesCubit drivesCubit;
  final TextEditingController controller;

  @override
  _FileSearchModalState createState() => _FileSearchModalState();
}

class _FileSearchModalState extends State<_FileSearchModal> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.text.isNotEmpty) {
      searchFiles(widget.controller.text);
    }

    widget.controller.addListener(() {
      debounceSearch(widget.controller.text);
    });
  }

  void debounceSearch(String query) {
    debounce(() => searchFiles(query));
  }

  Future<void> searchFiles(String query) async {
    if (mounted) {
      context.read<SearchBloc>().add(SearchQueryChanged(query));
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
                  SearchTextField(
                    controller: widget.controller,
                    onFieldSubmitted: (_) =>
                        searchFiles(widget.controller.text),
                  ),
                  const SizedBox(height: 16),
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
              SearchTextField(
                controller: widget.controller,
                onFieldSubmitted: (_) => searchFiles(widget.controller.text),
              ),
              const SizedBox(height: 16),
              _buildSearchResults(context, typography, colorTokens),
            ],
          ),
        ),
      );
    });
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
          if (state is SearchSuccess) {
            return ArDriveScrollBar(
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
            );
          } else if (state is SearchQueryEmpty) {
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
    final name = _resolveName(searchResult.result);
    final isHidden = _isHidden(searchResult.result);
    final leadingIcon = _getLeadingIcon(searchResult.result, colorTokens);
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

  bool _isHidden(dynamic result) {
    if (result is FileEntry) {
      return result.isHidden;
    } else if (result is FolderEntry) {
      return result.isHidden;
    } else {
      return false;
    }
  }

  String _resolveName(dynamic result) {
    if (result is FileEntry) return result.name;
    if (result is FolderEntry) return result.name;
    if (result is Drive) return result.name;
    return 'Unknown';
  }

  Widget _getLeadingIcon(
    dynamic result,
    ArDriveColorTokens colorTokens,
  ) {
    if (result is FileEntry) {
      return getIconForContentType(
        result.dataContentType ?? ContentType.octetStream,
        size: 24,
        color: colorTokens.textHigh,
      );
    } else if (result is FolderEntry) {
      return ArDriveIcons.folderOutline(
        color: colorTokens.textHigh,
      );
    } else if (result is Drive) {
      return result.privacy == DrivePrivacy.private.name
          ? ArDriveIcons.privateDrive(color: colorTokens.iconHigh)
          : ArDriveIcons.publicDrive(color: colorTokens.iconHigh);
    }

    return const Icon(Icons.error);
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
    if (searchResult.result is FileEntry) {
      _navigateToFile(context, searchResult.result as FileEntry);
    } else if (searchResult.result is FolderEntry) {
      context.read<DrivesCubit>().selectDrive(searchResult.drive.id);

      final otherDriveId = (searchResult.parentFolder == null)
          ? searchResult.drive.id
          : searchResult.parentFolder!.driveId;

      widget.driveDetailCubit.openFolder(
        otherDriveId: otherDriveId,
        folderId: searchResult.result.id,
      );

      Navigator.of(context).pop();
    } else if (searchResult.result is Drive) {
      context
          .read<DrivesCubit>()
          .selectDrive((searchResult.result as Drive).id);
      Navigator.of(context).pop();
    }
  }

  Future<void> _navigateToFile(
    BuildContext context,
    FileEntry result,
  ) async {
    final file = DriveDataTableItemMapper.fromFileEntryForSearchModal(
      result,
    );

    await Future.delayed(const Duration(milliseconds: 100));

    widget.drivesCubit.selectDrive(file.driveId);

    await Future.delayed(const Duration(milliseconds: 100));

    widget.driveDetailCubit.openFolder(
      otherDriveId: file.driveId,
      folderId: file.parentFolderId,
      selectedItemId: file.id,
    );

    late StreamSubscription<DriveDetailState> listener;

    listener = widget.driveDetailCubit.stream.listen((state) {
      if (state is DriveDetailLoadSuccess) {
        listener.cancel();
        // ignore: use_build_context_synchronously
        Navigator.of(context).pop();
      }
    });
  }
}
