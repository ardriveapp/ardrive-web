import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToMoveFolder(
  BuildContext context, {
  @required String driveId,
  @required String folderId,
}) =>
    showDialog(
      context: context,
      builder: (_) => FsEntryMoveForm(
        driveId: driveId,
        folderId: folderId,
      ),
    );

Future<void> promptToMoveFile(
  BuildContext context, {
  @required String driveId,
  @required String fileId,
}) =>
    showDialog(
      context: context,
      builder: (_) => FsEntryMoveForm(
        driveId: driveId,
        fileId: fileId,
      ),
    );

class FsEntryMoveForm extends StatelessWidget {
  final String driveId;
  final String folderId;
  final String fileId;

  FsEntryMoveForm({@required this.driveId, this.folderId, this.fileId})
      : assert(folderId != null || fileId != null);

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => FsEntryMoveCubit(
          driveId: driveId,
          folderId: folderId,
          fileId: fileId,
          arweave: context.repository<ArweaveService>(),
          driveDao: context.repository<DriveDao>(),
          profileBloc: context.bloc<ProfileBloc>(),
        ),
        child: BlocConsumer<FsEntryMoveCubit, FsEntryMoveState>(
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
          builder: (context, state) => AppDialog(
            title: state.isMovingFolder ? 'MOVE FOLDER' : 'MOVE FILE',
            contentPadding: EdgeInsets.zero,
            content: state is FsEntryMoveFolderLoadSuccess
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                        child: Container(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!state.viewingRootFolder)
                                TextButton.icon(
                                    icon: Icon(Icons.arrow_back),
                                    label: Text(
                                        'Back to "${state.viewingFolder.folder.name}" folder'),
                                    onPressed: () => context
                                        .bloc<FsEntryMoveCubit>()
                                        .loadParentFolder()),
                              Container(
                                height: 150,
                                width: 450,
                                child: ListView(
                                  shrinkWrap: true,
                                  children: [
                                    ...state.viewingFolder.subfolders.map(
                                      (f) => ListTile(
                                        key: ValueKey(f.id),
                                        dense: true,
                                        title: Text(f.name),
                                        trailing: IconButton(
                                          icon:
                                              Icon(Icons.keyboard_arrow_right),
                                          onPressed: () => context
                                              .bloc<FsEntryMoveCubit>()
                                              .loadFolder(f.id),
                                        ),
                                      ),
                                    ),
                                    ...state.viewingFolder.files
                                        .map((f) => ListTile(
                                              key: ValueKey(f.id),
                                              title: Text(f.name),
                                              enabled: false,
                                              dense: true,
                                            )),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: ButtonBar(
                          alignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (state is FsEntryMoveFolderLoadSuccess)
                              TextButton.icon(
                                icon: Icon(Icons.create_new_folder),
                                label: Text('CREATE FOLDER'),
                                onPressed: () => promptToCreateFolder(
                                  context,
                                  targetDriveId:
                                      state.viewingFolder.folder.driveId,
                                  targetFolderId: state.viewingFolder.folder.id,
                                ),
                              ),
                            ElevatedButton(
                              child: Text('MOVE HERE'),
                              onPressed: () =>
                                  context.bloc<FsEntryMoveCubit>().submit(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Container(),
          ),
        ),
      );
}
