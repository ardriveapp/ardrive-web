import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/file_download_dialog.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FileSearchModal extends StatefulWidget {
  const FileSearchModal({
    super.key,
    this.initialQuery,
    required this.driveDetailCubit,
  });

  final String? initialQuery;
  final DriveDetailCubit driveDetailCubit;

  @override
  State<FileSearchModal> createState() => _FileSearchModalState();
}

class _FileSearchModalState extends State<FileSearchModal> {
  List<SearchResult>? searchResults;

  @override
  initState() {
    super.initState();
    if (widget.initialQuery != null) {
      searchFiles(widget.initialQuery!);
      controller.text = widget.initialQuery!;
    }
  }

  Future<void> searchFiles(String query) async {
    final results = await context.read<DriveDao>().searchFiles(query);
    setState(() {
      searchResults = results;
    });
  }

  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colortokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ArDriveLoginModal(
      width: MediaQuery.of(context).size.width * 0.6,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Search Files',
            style: typography.heading1(
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
          ArDriveButtonNew(
            text: 'Search',
            onPressed: () => searchFiles(controller.text),
            typography: typography,
            variant: ButtonVariant.primary,
          ),
          const SizedBox(height: 16),
          if (searchResults != null)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: ListView.builder(
                itemCount: searchResults!.length,
                itemBuilder: (context, index) {
                  final search = searchResults![index];

                  Widget leading;
                  Widget trailing;
                  String name;

                  if (search.result is FileRevision) {
                    leading = getIconForContentType(
                      (search.result as FileRevision).dataContentType ??
                          ContentType.octetStream,
                    );
                    name = (search.result as FileRevision).name;

                    final trailingIcon = ArDriveIcons.download2(
                      color: colortokens.iconHigh,
                    );
                    trailing = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ArDriveIconButton(
                          icon: ArDriveIcons.newWindow(),
                          onPressed: () {
                            final file = DriveDataTableItemMapper.fromRevision(
                              search.result as FileRevision,
                              true,
                            );
                            Future.delayed(const Duration(milliseconds: 300))
                                .then((value) async {
                              // context
                              //     .read<DrivesCubit>()
                              //     .selectDrive(search.drive.id);
                              widget.driveDetailCubit.openFolder(
                                otherDriveId: file.driveId,
                                folderId: file.parentFolderId,
                              );
                              Future.delayed(const Duration(milliseconds: 500))
                                  .then(
                                (value) {
                                  widget.driveDetailCubit.selectDataItem(
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
                            if (search.result is FileRevision) {
                              promptToDownloadProfileFile(
                                context: context,
                                file: DriveDataTableItemMapper.fromRevision(
                                  search.result as FileRevision,
                                  true,
                                ),
                              );
                            } else if (search.result is FolderRevision) {
                              context
                                  .read<DrivesCubit>()
                                  .selectDrive(search.drive.id);
                              widget.driveDetailCubit.openFolder(
                                otherDriveId: search.folder!.driveId,
                                folderId:
                                    (search.result as FolderRevision).folderId,
                              );
                              Navigator.of(context).pop();
                            } else if (search.result is DriveRevision) {
                              context.read<DrivesCubit>().selectDrive(
                                  (search.result as DriveRevision).driveId);
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ],
                    );
                  } else if (search.result is FolderRevision) {
                    name = (search.result as FolderRevision).name;
                    leading = Icon(
                      Icons.folder,
                      color: colortokens.iconHigh,
                    );
                    final trailingIcon = ArDriveIcons.newWindow(
                      color: colortokens.iconHigh,
                    );
                    trailing = ArDriveIconButton(
                      icon: trailingIcon,
                      onPressed: () {
                        if (search.result is FileRevision) {
                          promptToDownloadProfileFile(
                            context: context,
                            file: DriveDataTableItemMapper.fromRevision(
                              search.result as FileRevision,
                              true,
                            ),
                          );
                        } else if (search.result is FolderRevision) {
                          context
                              .read<DrivesCubit>()
                              .selectDrive(search.drive.id);
                          widget.driveDetailCubit.openFolder(
                            otherDriveId: search.folder!.driveId,
                            folderId:
                                (search.result as FolderRevision).folderId,
                          );
                          Navigator.of(context).pop();
                        } else if (search.result is DriveRevision) {
                          context.read<DrivesCubit>().selectDrive(
                              (search.result as DriveRevision).driveId);
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  } else if (search.result is DriveRevision) {
                    name = (search.result as DriveRevision).name;
                    leading = ArDriveIcons.addDrive(
                      color: colortokens.iconHigh,
                    );
                    final trailingIcon = ArDriveIcons.newWindow(
                      color: colortokens.iconHigh,
                    );
                    trailing = ArDriveIconButton(
                      icon: trailingIcon,
                      onPressed: () {
                        if (search.result is FileRevision) {
                          promptToDownloadProfileFile(
                            context: context,
                            file: DriveDataTableItemMapper.fromRevision(
                              search.result as FileRevision,
                              true,
                            ),
                          );
                        } else if (search.result is FolderRevision) {
                          context
                              .read<DrivesCubit>()
                              .selectDrive(search.drive.id);
                          widget.driveDetailCubit.openFolder(
                            otherDriveId: search.folder!.driveId,
                            folderId:
                                (search.result as FolderRevision).folderId,
                          );
                          Navigator.of(context).pop();
                        } else if (search.result is DriveRevision) {
                          context.read<DrivesCubit>().selectDrive(
                              (search.result as DriveRevision).driveId);
                          Navigator.of(context).pop();
                        }
                      },
                    );
                  } else {
                    throw Exception('Unknown search result type');
                  }

                  return HoverWidget(
                    hoverScale: 1,
                    child: SizedBox(
                      child: ArDriveClickArea(
                        child: ListTile(
                          onTap: () {
                            if (search.result is FileRevision) {
                              promptToDownloadProfileFile(
                                context: context,
                                file: DriveDataTableItemMapper.fromRevision(
                                  search.result as FileRevision,
                                  true,
                                ),
                              );
                            } else if (search.result is FolderRevision) {
                              final drivesCubit = context.read<DrivesCubit>();
                              Navigator.pop(context);
                              Future.delayed(const Duration(milliseconds: 300))
                                  .then((value) {
                                drivesCubit.selectDrive(search.drive.id);
                                widget.driveDetailCubit.openFolder(
                                  otherDriveId: search.folder!.driveId,
                                  folderId: (search.result as FolderRevision)
                                      .folderId,
                                );
                              });
                            } else if (search.result is DriveRevision) {
                              final drivesCubit = context.read<DrivesCubit>();
                              Navigator.of(context).pop();

                              Future.delayed(const Duration(milliseconds: 300))
                                  .then((value) {
                                drivesCubit.selectDrive(
                                    (search.result as DriveRevision).driveId);
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
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
