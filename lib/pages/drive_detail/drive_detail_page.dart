import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moor/moor.dart' show OrderingMode;
import 'package:responsive_builder/responsive_builder.dart';
import 'package:timeago/timeago.dart';
import 'package:url_launcher/link.dart';

part 'components/drive_detail_actions_row.dart';
part 'components/drive_detail_breadcrumb_row.dart';
part 'components/drive_detail_data_table.dart';
part 'components/drive_detail_folder_empty_card.dart';
part 'components/fs_entry_side_sheet.dart';

class DriveDetailPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: BlocBuilder<DriveDetailCubit, DriveDetailState>(
          builder: (context, state) {
            if (state is DriveDetailLoadInProgress) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is DriveDetailLoadSuccess) {
              return ScreenTypeLayout(
                desktop: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      state.currentDrive.name,
                                      style:
                                          Theme.of(context).textTheme.headline5,
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
                                        child: _buildDataTable(context, state),
                                      ),
                                    ],
                                  )
                                else
                                  DriveDetailFolderEmptyCard(
                                      promptToAddFiles:
                                          state.hasWritePermissions),
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
                  ],
                ),
                mobile: state.showSelectedItemDetails
                    ? FsEntrySideSheet(
                        driveId: state.currentDrive.id,
                        folderId: state.selectedItemIsFolder
                            ? state.selectedItemId
                            : null,
                        fileId: !state.selectedItemIsFolder
                            ? state.selectedItemId
                            : null,
                      )
                    : Scrollbar(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 32, horizontal: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      state.currentDrive.name,
                                      style:
                                          Theme.of(context).textTheme.headline5,
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
                                        child: _buildDataTable(context, state),
                                      ),
                                    ],
                                  )
                                else
                                  DriveDetailFolderEmptyCard(
                                      promptToAddFiles:
                                          state.hasWritePermissions),
                              ],
                            ),
                          ),
                        ),
                      ),
              );
            } else {
              return const SizedBox();
            }
          },
        ),
      );
}
