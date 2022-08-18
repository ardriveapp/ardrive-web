import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_detail/selected_item.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/congestion_warning_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToMove(
  BuildContext context, {
  required String driveId,
  required List<SelectedItem> selectedItems,
}) =>
    showCongestionDependentModalDialog(
        context,
        () => showDialog(
              context: context,
              builder: (_) => BlocProvider(
                create: (context) => FsEntryMoveBloc(
                  driveId: driveId,
                  selectedItems: selectedItems,
                  arweave: context.read<ArweaveService>(),
                  driveDao: context.read<DriveDao>(),
                  profileCubit: context.read<ProfileCubit>(),
                  syncCubit: context.read<SyncCubit>(),
                )..add(const FsEntryMoveInitial()),
                child: FsEntryMoveForm(),
              ),
            ));

class FsEntryMoveForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FsEntryMoveBloc, FsEntryMoveState>(
        listener: (context, state) {
          if (state is FolderEntryMoveInProgress) {
            showProgressDialog(
                context, appLocalizationsOf(context).movingFolderEmphasized);
          } else if (state is FileEntryMoveInProgress) {
            showProgressDialog(
                context, appLocalizationsOf(context).movingFileEmphasized);
          } else if (state is FsEntryMoveSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is FsEntryMoveWalletMismatch) {
            Navigator.pop(context);
          } else if (state is FsEntryMoveNameConflict) {
            Navigator.pop(context);
            Navigator.pop(context);
            showDialog(
              context: context,
              builder: (BuildContext context) => AppDialog(
                dismissable: true,
                title: appLocalizationsOf(context).nameConflict,
                content: SizedBox(
                  width: kSmallDialogWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Text(
                          appLocalizationsOf(context)
                              .entityAlreadyExists(state.name),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(appLocalizationsOf(context).ok)),
                ],
              ),
            );
          }
        },
        builder: (context, state) {
          Widget _buildButtonBar() => ButtonBar(
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child:
                          Text(appLocalizationsOf(context).cancelEmphasized)),
                  ElevatedButton(
                    onPressed: () => context.read<FsEntryMoveBloc>().submit(),
                    child: Text(appLocalizationsOf(context).moveHereEmphasized),
                  ),
                ],
              );
          Widget _buildCreateFolderButton() {
            if (state is FsEntryMoveFolderLoadSuccess) {
              return TextButton.icon(
                icon: const Icon(Icons.create_new_folder),
                label: Text(appLocalizationsOf(context).createFolderEmphasized),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => BlocProvider(
                    create: (context) => FolderCreateCubit(
                      driveId: state.viewingFolder.folder.driveId,
                      parentFolderId: state.viewingFolder.folder.id,
                      profileCubit: context.read<ProfileCubit>(),
                      arweave: context.read<ArweaveService>(),
                      driveDao: context.read<DriveDao>(),
                    ),
                    child: FolderCreateForm(),
                  ),
                ),
              );
            } else {
              return Container();
            }
          }

          return AppDialog(
            title: state.isMovingFolder
                ? appLocalizationsOf(context).moveFolderEmphasized
                : appLocalizationsOf(context).moveFileEmphasized,
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
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextButton(
                                style: TextButton.styleFrom(
                                    textStyle:
                                        Theme.of(context).textTheme.subtitle2,
                                    padding: const EdgeInsets.all(16)),
                                onPressed: () => context
                                    .read<FsEntryMoveBloc>()
                                    .loadParentFolder(),
                                child: ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.arrow_back),
                                  title: Text(appLocalizationsOf(context)
                                      .backToFolder(
                                          state.viewingFolder.folder.name)),
                                )),
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
                                          .read<FsEntryMoveBloc>()
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
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              _buildCreateFolderButton(),
                              _buildButtonBar(),
                            ],
                          ),
                        )
                      ],
                    ),
                  )
                : const SizedBox(),
          );
        },
      );
}
