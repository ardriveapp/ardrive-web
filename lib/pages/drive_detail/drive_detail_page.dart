import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components/drive_detail_actions_row.dart';
import 'components/drive_detail_breadcrumb_row.dart';
import 'components/drive_detail_folder_empty_card.dart';
import 'components/fs_entry_side_sheet.dart';
import 'components/table_rows.dart';

class DriveDetailPage extends StatelessWidget {
  final String driveId;

  DriveDetailPage({Key key, this.driveId}) : super(key: key);

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: BlocConsumer<DriveDetailCubit, DriveDetailState>(
          listener: (context, state) {
            if (state is DriveDetailLoadSuccess) {
              Router.navigate(
                context,
                () => Router.of(context).delegate.navigateToDriveDetailPage(
                    state.currentDrive.id, state.currentFolder.folder.id),
              );
            }
          },
          builder: (context, state) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state is DriveDetailLoadSuccess) ...{
                Expanded(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 32, horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  state.currentDrive.name,
                                  style: Theme.of(context).textTheme.headline5,
                                ),
                                DriveDetailActionRow(),
                              ],
                            ),
                            DriveDetailBreadcrumbRow(
                                path: state.currentFolder.folder.path),
                            if (state.currentFolder.subfolders.isNotEmpty ||
                                state.currentFolder.files.isNotEmpty)
                              Row(
                                children: [
                                  Expanded(
                                    child: DataTable(
                                      showCheckboxColumn: false,
                                      columns: buildTableColumns(),
                                      rows: [
                                        ...state.currentFolder.subfolders.map(
                                          (folder) => buildFolderRow(
                                            context: context,
                                            folder: folder,
                                            selected: folder.id ==
                                                state.selectedItemId,
                                            onPressed: () {
                                              final bloc = context
                                                  .read<DriveDetailCubit>();
                                              if (folder.id ==
                                                  state.selectedItemId) {
                                                bloc.openFolderAtPath(
                                                    folder.path);
                                              } else {
                                                bloc.selectItem(
                                                  folder.id,
                                                  isFolder: true,
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                        ...state.currentFolder.files.map(
                                          (file) => buildFileRow(
                                            context: context,
                                            file: file,
                                            selected:
                                                file.id == state.selectedItemId,
                                            onPressed: () async {
                                              final bloc = context
                                                  .read<DriveDetailCubit>();
                                              if (file.id ==
                                                  state.selectedItemId) {
                                                bloc.toggleSelectedItemDetails();
                                              } else {
                                                await bloc.selectItem(file.id);
                                              }
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            else
                              DriveDetailFolderEmptyCard(
                                  promptToAddFiles: state.hasWritePermissions),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (state.showSelectedItemDetails) ...{
                  VerticalDivider(width: 1),
                  FsEntrySideSheet(
                    driveId: state.currentDrive.id,
                    folderId: state.selectedItemIsFolder
                        ? state.selectedItemId
                        : null,
                    fileId: !state.selectedItemIsFolder
                        ? state.selectedItemId
                        : null,
                  ),
                }
              }
            ],
          ),
        ),
      );
}
