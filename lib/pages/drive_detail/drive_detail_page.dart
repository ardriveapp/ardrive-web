import 'dart:math';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_detail/selected_item.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/pages/drive_detail/components/drive_file_drop_zone.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/num_to_string_parsers.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intersperse/intersperse.dart';
import 'package:moor/moor.dart' show OrderingMode;
import 'package:responsive_builder/responsive_builder.dart';
import 'package:timeago/timeago.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/app_localizations_wrapper.dart';
import 'components/custom_paginated_data_table.dart';

part 'components/drive_detail_actions_row.dart';
part 'components/drive_detail_breadcrumb_row.dart';
part 'components/drive_detail_data_list.dart';
part 'components/drive_detail_data_table.dart';
part 'components/drive_detail_data_table_source.dart';
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
                desktop: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        width: 400,
                                        child: Text(
                                          state.currentDrive.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline5,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DriveDetailActionRow(),
                                  ],
                                ),
                                DriveDetailBreadcrumbRow(
                                  path: state.folderInView.folder.path,
                                ),
                                if (state.folderInView.subfolders.isNotEmpty ||
                                    state.folderInView.files.isNotEmpty)
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child:
                                              _buildDataTable(context, state),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  DriveDetailFolderEmptyCard(
                                      promptToAddFiles:
                                          state.hasWritePermissions),
                              ],
                            ),
                          ),
                        ),
                        if (state.showSelectedItemDetails) ...{
                          VerticalDivider(width: 1),
                          FsEntrySideSheet(
                            driveId: state.currentDrive.id,
                            maybeSelectedItem: state.maybeSelectedItem,
                          ),
                        }
                      ],
                    ),
                    if (kIsWeb)
                      DriveFileDropZone(
                        driveId: state.currentDrive.id,
                        folderId: state.folderInView.folder.id,
                      ),
                  ],
                ),
                mobile: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!state.showSelectedItemDetails)
                      Expanded(
                        child: Scrollbar(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      state.currentDrive.name,
                                      style:
                                          Theme.of(context).textTheme.headline5,
                                    ),
                                    SizedBox(
                                      height: 16,
                                    ),
                                    DriveDetailActionRow()
                                  ],
                                ),
                                DriveDetailBreadcrumbRow(
                                  path: state.folderInView.folder.path,
                                ),
                                if (state.folderInView.subfolders.isNotEmpty ||
                                    state.folderInView.files.isNotEmpty)
                                  Expanded(
                                    child: _buildDataList(context, state),
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
                    if (state.showSelectedItemDetails)
                      Expanded(
                        child: FsEntrySideSheet(
                          driveId: state.currentDrive.id,
                          maybeSelectedItem: state.maybeSelectedItem,
                        ),
                      )
                  ],
                ),
              );
            } else {
              return const SizedBox();
            }
          },
        ),
      );
}
