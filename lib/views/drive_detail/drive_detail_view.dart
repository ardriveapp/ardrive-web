import 'package:ardrive/blocs/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components/drive_detail_actions_row.dart';
import 'components/drive_detail_breadcrumb_row.dart';
import 'components/drive_detail_folder_empty_card.dart';
import 'components/drive_info_side_sheet.dart';
import 'components/table_rows.dart';

class DriveDetailView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: BlocBuilder<DriveDetailCubit, DriveDetailState>(
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
                                    columns: const <DataColumn>[
                                      DataColumn(label: Text('Name')),
                                      DataColumn(label: Text('File size')),
                                    ],
                                    rows: [
                                      ...state.currentFolder.subfolders.map(
                                        (folder) => buildFolderRow(
                                          context: context,
                                          folder: folder,
                                          selected:
                                              folder.id == state.selectedItemId,
                                          onPressed: () {
                                            final bloc = context
                                                .bloc<DriveDetailCubit>();
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
                                                .bloc<DriveDetailCubit>();
                                            if (file.id ==
                                                state.selectedItemId) {
                                              bloc.toggleSelectedItemDetails();
                                            } else {
                                              bloc.selectItem(file.id);
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
                DriveInfoSideSheet(
                    driveId: state.currentDrive.id,
                    folderId: state.selectedItemIsFolder
                        ? state.selectedItemId
                        : null,
                    fileId: !state.selectedItemIsFolder
                        ? state.selectedItemId
                        : null),
              }
            }
          ],
        ),
      ),
    );
  }
}
