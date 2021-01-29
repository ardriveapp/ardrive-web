import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import 'components.dart';

Future<void> promptToMoveFolder(
  BuildContext context, {
  @required String driveId,
  @required String folderId,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => FsEntryMoveCubit(
          driveId: driveId,
          folderId: folderId,
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
          profileCubit: context.read<ProfileCubit>(),
          syncCubit: context.read<SyncCubit>(),
        ),
        child: FsEntryMoveForm(),
      ),
    );

Future<void> promptToMoveFile(
  BuildContext context, {
  @required String driveId,
  @required String fileId,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => FsEntryMoveCubit(
          driveId: driveId,
          fileId: fileId,
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
          profileCubit: context.read<ProfileCubit>(),
        ),
        child: FsEntryMoveForm(),
      ),
    );

class FsEntryMoveForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FsEntryMoveCubit, FsEntryMoveState>(
        listener: (context, state) {
          if (state is FolderEntryMoveInProgress) {
            showProgressDialog(context, 'MOVING FOLDER...');
          } else if (state is FileEntryMoveInProgress) {
            showProgressDialog(context, 'MOVING FILE...');
          } else if (state is FolderEntryMoveSuccess ||
              state is FileEntryMoveSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          }
        },
        builder: (context, state) {
          Widget _buildButtonBar() => ButtonBar(
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('CANCEL')),
                  ElevatedButton(
                    child: Text('MOVE HERE'),
                    onPressed: () => context.read<FsEntryMoveCubit>().submit(),
                  ),
                ],
              );
          Widget _buildCreateFolderButton() {
            if (state is FsEntryMoveFolderLoadSuccess) {
              return TextButton.icon(
                icon: const Icon(Icons.create_new_folder),
                label: Text('CREATE FOLDER'),
                onPressed: () => promptToCreateFolder(
                  context,
                  driveId: state.viewingFolder.folder.driveId,
                  parentFolderId: state.viewingFolder.folder.id,
                ),
              );
            } else {
              return Container();
            }
          }

          return AppDialog(
            title: state.isMovingFolder ? 'MOVE FOLDER' : 'MOVE FILE',
            contentPadding: EdgeInsets.zero,
            content: state is FsEntryMoveFolderLoadSuccess
                ? SizedBox(
                    width: kLargeDialogWidth,
                    height: 325,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        if (!state.viewingRootFolder)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 16, right: 16, bottom: 8),
                            child: TextButton.icon(
                                style: TextButton.styleFrom(
                                    textStyle:
                                        Theme.of(context).textTheme.subtitle2,
                                    padding: const EdgeInsets.all(16)),
                                icon: const Icon(Icons.arrow_back),
                                label: Text(
                                    'Back to "${state.viewingFolder.folder.name}" folder'),
                                onPressed: () => context
                                    .read<FsEntryMoveCubit>()
                                    .loadParentFolder()),
                          ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Scrollbar(
                              child: ListView(
                                shrinkWrap: true,
                                children: [
                                  ...state.viewingFolder.subfolders.map(
                                    (f) => ListTile(
                                      key: ValueKey(f.id),
                                      dense: true,
                                      leading: const Icon(Icons.folder),
                                      title: Text(f.name),
                                      onTap: () => context
                                          .read<FsEntryMoveCubit>()
                                          .loadFolder(f.id),
                                      trailing:
                                          Icon(Icons.keyboard_arrow_right),
                                      // Do not allow users to navigate into the folder they are currently trying to move.
                                      enabled: f.id != state.movingEntryId,
                                    ),
                                  ),
                                  ...state.viewingFolder.files.map(
                                    (f) => ListTile(
                                      key: ValueKey(f.id),
                                      leading: Icon(Icons.insert_drive_file),
                                      title: Text(f.name),
                                      enabled: false,
                                      dense: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Divider(),
                        Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: ScreenTypeLayout(
                              desktop: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildCreateFolderButton(),
                                  _buildButtonBar(),
                                ],
                              ),
                              mobile: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                children: [
                                  _buildCreateFolderButton(),
                                  _buildButtonBar(),
                                ],
                              ),
                            )),
                      ],
                    ),
                  )
                : const SizedBox(),
          );
        },
      );
}
