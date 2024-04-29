import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/file_download_dialog.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/search/domain/bloc/search_bloc.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FileSearchModal extends StatelessWidget {
  const FileSearchModal(
      {super.key, required this.driveDetailCubit, this.initialQuery});

  final DriveDetailCubit driveDetailCubit;
  final String? initialQuery;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        RepositoryProvider<ArDriveSearchRepository>(
          create: (context) => ArDriveSearchRepository(
            context.read<DriveDao>(),
          ),
        ),
        BlocProvider(
          create: (context) => SearchBloc(
            context.read<ArDriveSearchRepository>(),
          )..add(SearchQueryChanged(initialQuery ?? '')),
        ),
      ],
      child: _FileSearchModal(
        driveDetailCubit: driveDetailCubit,
        initialQuery: initialQuery,
      ),
    );
  }
}

class _FileSearchModal extends StatefulWidget {
  const _FileSearchModal({
    required this.driveDetailCubit,
    this.initialQuery,
  });

  final String? initialQuery;
  final DriveDetailCubit driveDetailCubit;

  @override
  State<_FileSearchModal> createState() => __FileSearchModalState();
}

class __FileSearchModalState extends State<_FileSearchModal> {
  @override
  initState() {
    super.initState();
    if (widget.initialQuery != null) {
      controller.text = widget.initialQuery!;
      controller.addListener(() {
        // add a debounce
        debounce(() => searchFiles(controller.text));
      });
    }
  }

  Future<void> searchFiles(String query) async {
    context.read<SearchBloc>().add(SearchQueryChanged(query));
  }

  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colortokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveLoginModal(
      width: MediaQuery.of(context).size.width * 0.6,
      content: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Search for a file, folder or drive',
              style: typography.heading4(
                  color: colortokens.textHigh, fontWeight: ArFontWeight.bold),
            ),
            const SizedBox(height: 16),
            ArDriveTextFieldNew(
              controller: controller,
              label: 'Search',
              hintText: 'Search for files',
              onFieldSubmitted: (p0) => searchFiles(controller.text),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: BlocBuilder<SearchBloc, SearchState>(
                builder: (context, state) {
                  if (state is SearchSuccess) {
                    final searchResults = state.results;
                    return SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: ListView.builder(
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final search = searchResults[index];

                          Widget leading;
                          Widget trailing;
                          String name;

                          if (search.result is FileEntry) {
                            leading = getIconForContentType(
                              (search.result as FileEntry).dataContentType ??
                                  ContentType.octetStream,
                              size: 24,
                            );
                            name = (search.result as FileEntry).name;

                            final trailingIcon = ArDriveIcons.download2(
                              color: colortokens.iconHigh,
                            );

                            trailing = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ArDriveIconButton(
                                  icon: ArDriveIcons.newWindow(),
                                  onPressed: () {
                                    final file = DriveDataTableItemMapper
                                        .fromFileEntryForSearchModal(
                                      search.result as FileEntry,
                                    );
                                    Future.delayed(
                                            const Duration(milliseconds: 300))
                                        .then((value) async {
                                      widget.driveDetailCubit.openFolder(
                                        otherDriveId: file.driveId,
                                        folderId: file.parentFolderId,
                                      );
                                      Future.delayed(
                                              const Duration(milliseconds: 500))
                                          .then(
                                        (value) {
                                          widget.driveDetailCubit
                                              .selectDataItem(
                                            file,
                                            openSelectedPage: true,
                                          );
                                          Navigator.of(context).pop();
                                        },
                                      );
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                ArDriveIconButton(
                                  icon: trailingIcon,
                                  onPressed: () {
                                    if (search.result is FileEntry) {
                                      promptToDownloadProfileFile(
                                        context: context,
                                        file: DriveDataTableItemMapper
                                            .fromFileEntryForSearchModal(
                                          search.result as FileEntry,
                                        ),
                                      );
                                    } else if (search.result is FolderEntry) {
                                      context
                                          .read<DrivesCubit>()
                                          .selectDrive(search.drive.id);
                                      widget.driveDetailCubit.openFolder(
                                        otherDriveId: search.folder!.driveId,
                                        folderId:
                                            (search.result as FolderEntry).id,
                                      );
                                      Navigator.of(context).pop();
                                    } else if (search.result is Drive) {
                                      context.read<DrivesCubit>().selectDrive(
                                          (search.result as Drive).id);
                                      Navigator.of(context).pop();
                                    }
                                  },
                                ),
                              ],
                            );
                          } else if (search.result is FolderEntry) {
                            name = (search.result as FolderEntry).name;
                            leading = ArDriveIcons.folderOutline();
                            final trailingIcon = ArDriveIcons.newWindow(
                              color: colortokens.iconHigh,
                            );
                            trailing = ArDriveIconButton(
                              icon: trailingIcon,
                              onPressed: () {
                                if (search.result is FileEntry) {
                                  promptToDownloadProfileFile(
                                    context: context,
                                    file: DriveDataTableItemMapper
                                        .fromFileEntryForSearchModal(
                                      search.result as FileEntry,
                                    ),
                                  );
                                } else if (search.result is FolderEntry) {
                                  context
                                      .read<DrivesCubit>()
                                      .selectDrive(search.drive.id);
                                  widget.driveDetailCubit.openFolder(
                                    otherDriveId: search.folder!.driveId,
                                    folderId: (search.result as FolderEntry).id,
                                  );
                                  Navigator.of(context).pop();
                                } else if (search.result is Drive) {
                                  context
                                      .read<DrivesCubit>()
                                      .selectDrive((search.result as Drive).id);
                                  Navigator.of(context).pop();
                                }
                              },
                            );
                          } else if (search.result is Drive) {
                            final drive = (search.result as Drive);
                            name = drive.name;
                            final isPrivate =
                                drive.privacy == DrivePrivacy.private.name;

                            leading = isPrivate
                                ? ArDriveIcons.privateDrive(
                                    color: colortokens.iconHigh,
                                  )
                                : ArDriveIcons.publicDrive(
                                    color: colortokens.iconHigh,
                                  );
                            final trailingIcon = ArDriveIcons.newWindow(
                              color: colortokens.iconHigh,
                            );
                            trailing = ArDriveIconButton(
                              icon: trailingIcon,
                              onPressed: () {
                                if (search.result is FileEntry) {
                                  promptToDownloadProfileFile(
                                    context: context,
                                    file: DriveDataTableItemMapper
                                        .fromFileEntryForSearchModal(
                                      search.result as FileEntry,
                                    ),
                                  );
                                } else if (search.result is FolderEntry) {
                                  context
                                      .read<DrivesCubit>()
                                      .selectDrive(search.drive.id);
                                  widget.driveDetailCubit.openFolder(
                                    otherDriveId: search.folder!.driveId,
                                    folderId: (search.result as FolderEntry).id,
                                  );
                                  Navigator.of(context).pop();
                                } else if (search.result is Drive) {
                                  context
                                      .read<DrivesCubit>()
                                      .selectDrive((search.result as Drive).id);
                                  Navigator.of(context).pop();
                                }
                              },
                            );
                          } else {
                            throw Exception('Unknown search result type');
                          }

                          return HoverWidget(
                            hoverScale: 1,
                            child: ArDriveClickArea(
                              child: ListTile(
                                onTap: () {
                                  if (search.result is FileEntry) {
                                    promptToDownloadProfileFile(
                                      context: context,
                                      file: DriveDataTableItemMapper
                                          .fromFileEntryForSearchModal(
                                        search.result as FileEntry,
                                      ),
                                    );
                                  } else if (search.result is FolderEntry) {
                                    final drivesCubit =
                                        context.read<DrivesCubit>();
                                    Navigator.pop(context);
                                    Future.delayed(
                                            const Duration(milliseconds: 300))
                                        .then((value) {
                                      drivesCubit.selectDrive(search.drive.id);
                                      widget.driveDetailCubit.openFolder(
                                        otherDriveId: search.folder!.driveId,
                                        folderId:
                                            (search.result as FolderEntry).id,
                                      );
                                    });
                                  } else if (search.result is Drive) {
                                    final drivesCubit =
                                        context.read<DrivesCubit>();
                                    Navigator.of(context).pop();

                                    Future.delayed(
                                            const Duration(milliseconds: 300))
                                        .then((value) {
                                      drivesCubit.selectDrive(
                                          (search.result as Drive).id);
                                    });
                                  }
                                },
                                leading: leading,
                                title: Text(
                                  name,
                                  style: typography.paragraphXLarge(
                                    color: colortokens.textHigh,
                                    fontWeight: ArFontWeight.bold,
                                  ),
                                ),
                                trailing: trailing,
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Drive: ${search.drive.name}',
                                      style: typography.paragraphNormal(
                                        color: colortokens.textLow,
                                        fontWeight: ArFontWeight.semiBold,
                                      ),
                                    ),
                                    if (search.folder != null)
                                      Text(
                                        'Folder: ${search.folder!.name}',
                                        style: typography.paragraphNormal(
                                          color: colortokens.textLow,
                                          fontWeight: ArFontWeight.semiBold,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  } else if (state is SearchQueryEmpty) {
                    return Center(
                      child: Text(
                        'Please search for files',
                        style: typography.paragraphNormal(
                          color: colortokens.textHigh,
                        ),
                      ),
                    );
                  }

                  return Center(
                    child: Text(
                      'No results found. Please try again.',
                      style: typography.paragraphNormal(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
