import 'package:ardrive/blocs/blocs.dart';
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
}) {
  return showCongestionDependentModalDialog(context, () {
    return showDialog(
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
        child: const FsEntryMoveForm(),
      ),
    );
  });
}

class FsEntryMoveForm extends StatelessWidget {
  const FsEntryMoveForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FsEntryMoveBloc, FsEntryMoveState>(
      listener: (context, state) {
        if (state is FsEntryMoveLoadInProgress) {
          showProgressDialog(
              context, appLocalizationsOf(context).movingFolderEmphasized);
        } else if (state is FsEntryMoveSuccess) {
          Navigator.pop(context);
        } else if (state is FsEntryMoveWalletMismatch) {
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        Widget _buildButtonBar(FolderEntry folderInView) {
          return ButtonBar(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  appLocalizationsOf(context).cancelEmphasized,
                ),
              ),
              ElevatedButton(
                onPressed: () => context
                    .read<FsEntryMoveBloc>()
                    .add(FsEntryMoveSubmit(folderInView: folderInView)),
                child: Text(appLocalizationsOf(context).moveHereEmphasized),
              ),
            ],
          );
        }

        Widget _buildCreateFolderButton() {
          if (state is FsEntryMoveLoadSuccess) {
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
                  child: const FolderCreateForm(),
                ),
              ),
            );
          } else {
            return Container();
          }
        }

        return Builder(builder: (context) {
          if (state is FsEntryMoveNameConflict) {
            return AppDialog(
              dismissable: true,
              title: appLocalizationsOf(context).nameConflict,
              content: SizedBox(
                width: kSmallDialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      appLocalizationsOf(context)
                          .itemMoveNameConflict(state.folderInView.name),
                    ),
                    for (final itemName in state.conflictingFileNames() +
                        state.conflictingFolderNames())
                      Text(itemName),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(appLocalizationsOf(context).cancelEmphasized)),
                TextButton(
                    onPressed: () {
                      context.read<FsEntryMoveBloc>().add(
                            FsEntryMoveSkipConflicts(
                              folderInView: state.folderInView,
                              conflictingItems: state.conflictingItems,
                            ),
                          );
                    },
                    child: Text(appLocalizationsOf(context).skipEmphasized)),
              ],
            );
          }
          if (state is FsEntryMoveLoadSuccess) {
            return AppDialog(
              title: appLocalizationsOf(context).moveItems,
              contentPadding: EdgeInsets.zero,
              content: SizedBox(
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
                            onPressed: () {
                              context.read<FsEntryMoveBloc>().add(
                                    FsEntryMoveGoBackToParent(
                                      folderInView: state.viewingFolder.folder,
                                    ),
                                  );
                            },
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
                                  onTap: () {
                                    context.read<FsEntryMoveBloc>().add(
                                          FsEntryMoveUpdateTargetFolder(
                                            folderId: f.id,
                                          ),
                                        );
                                  },

                                  trailing:
                                      const Icon(Icons.keyboard_arrow_right),
                                  // Do not allow users to navigate into the folder they are currently trying to move.
                                  enabled: state.itemsToMove
                                      .where((item) => item.id == f.id)
                                      .isEmpty,
                                ),
                              ),
                              ...state.viewingFolder.files.map(
                                (f) => ListTile(
                                  key: ValueKey(f.id),
                                  leading: const Icon(Icons.insert_drive_file),
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
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          _buildCreateFolderButton(),
                          _buildButtonBar(state.viewingFolder.folder),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            );
          } else {
            return const SizedBox();
          }
        });
      },
    );
  }
}
