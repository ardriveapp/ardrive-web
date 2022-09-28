import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/fs_entry_preview/fs_entry_preview_cubit.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/csv_export_dialog.dart';
import 'package:ardrive/components/drive_detach_dialog.dart';
import 'package:ardrive/components/drive_rename_form.dart';
import 'package:ardrive/components/ghost_fixer_form.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/pages/drive_detail/components/drive_file_drop_zone.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/num_to_string_parsers.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:drift/drift.dart' show OrderingMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intersperse/intersperse.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:timeago/timeago.dart';

import 'components/custom_paginated_data_table.dart';

part 'components/drive_detail_actions_row.dart';
part 'components/drive_detail_breadcrumb_row.dart';
part 'components/drive_detail_data_list.dart';
part 'components/drive_detail_data_table.dart';
part 'components/drive_detail_data_table_source.dart';
part 'components/drive_detail_folder_empty_card.dart';
part 'components/fs_entry_preview_widget.dart';
part 'components/fs_entry_side_sheet.dart';

class DriveDetailPage extends StatefulWidget {
  const DriveDetailPage({Key? key}) : super(key: key);

  @override
  State<DriveDetailPage> createState() => _DriveDetailPageState();
}

class _DriveDetailPageState extends State<DriveDetailPage> {
  bool checkboxEnabled = false;
  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: BlocBuilder<DriveDetailCubit, DriveDetailState>(
        builder: (context, state) {
          if (state is DriveDetailLoadInProgress) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is DriveDetailLoadSuccess) {
            return ScreenTypeLayout(
              desktop:
                  BlocListener<KeyboardListenerBloc, KeyboardListenerState>(
                listener: (context, keyListenerState) {
                  // Only allow multiselect on user drives and only if logged in
                  if (keyListenerState is KeyboardListenerCtrlMetaPressed &&
                      state.hasWritePermissions) {
                    checkboxEnabled = keyListenerState.isPressed;
                    context
                        .read<DriveDetailCubit>()
                        .setMultiSelect(checkboxEnabled);
                    setState(() => {});
                  }
                },
                child: Stack(
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
                                      child: SizedBox(
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
                                    const DriveDetailActionRow(),
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
                                          child: _buildDataTable(
                                            state: state,
                                            context: context,
                                            checkBoxEnabled: state.multiselect,
                                          ),
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
                          const VerticalDivider(width: 1),
                          FsEntrySideSheet(
                            driveId: state.currentDrive.id,
                            drivePrivacy: state.currentDrive.privacy,
                            maybeSelectedItem: state.selectedItems.isNotEmpty
                                ? state.selectedItems.first
                                : null,
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
                                  const SizedBox(
                                    height: 16,
                                  ),
                                  const DriveDetailActionRow()
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
                        drivePrivacy: state.currentDrive.privacy,
                        maybeSelectedItem: state.selectedItems.isNotEmpty
                            ? state.selectedItems.first
                            : null,
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
}
