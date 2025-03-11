import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToMove(
  BuildContext parentContext, {
  required String driveId,
  required List<ArDriveDataTableItem> selectedItems,
}) {
  return showArDriveDialog(
    parentContext,
    content: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => FsEntryMoveBloc(
            crypto: ArDriveCrypto(),
            driveId: driveId,
            selectedItems: selectedItems,
            arweave: context.read<ArweaveService>(),
            turboUploadService: context.read<TurboUploadService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            syncCubit: context.read<SyncCubit>(),
          )..add(const FsEntryMoveInitial()),
        ),
        BlocProvider.value(
          value: parentContext.read<DriveDetailCubit>(),
        )
      ],
      child: const FsEntryMoveForm(),
    ),
  );
}

class FsEntryMoveForm extends StatelessWidget {
  const FsEntryMoveForm({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FsEntryMoveBloc, FsEntryMoveState>(
      listener: (context, state) {
        if (state is FsEntryMoveLoadInProgress) {
          showProgressDialog(
            context,
            title: appLocalizationsOf(context).movingItemsEmphasized,
          );
        } else if (state is FsEntryMoveSuccess) {
          Navigator.pop(context);
          Navigator.pop(context);
        } else if (state is FsEntryMoveWalletMismatch) {
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        return BlocBuilder<DriveDetailCubit, DriveDetailState>(
          builder: (context, driveDetailState) {
            return Builder(builder: (context) {
              final typography = ArDriveTypographyNew.of(context);

              if (state is FsEntryMoveNameConflict) {
                return ArDriveStandardModalNew(
                  title: appLocalizationsOf(context).nameConflict,
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(
                        appLocalizationsOf(context)
                            .itemMoveNameConflict(state.folderInView.name),
                        style: typography.paragraphNormal(),
                      ),
                      for (final itemName in state.conflictingFileNames() +
                          state.conflictingFolderNames())
                        Text(
                          itemName,
                          style: typography.paragraphNormal(),
                        ),
                    ],
                  ),
                  actions: [
                    ModalAction(
                      action: () {
                        Navigator.pop(context);
                      },
                      title: appLocalizationsOf(context).cancelEmphasized,
                    ),
                    if (!state.areAllItemsConflicting())
                      ModalAction(
                        action: () {
                          context.read<FsEntryMoveBloc>().add(
                                FsEntryMoveSkipConflicts(
                                  folderInView: state.folderInView,
                                  conflictingItems: state.conflictingItems,
                                  showHiddenItems: context
                                      .read<GlobalHideBloc>()
                                      .state is ShowingHiddenItems,
                                ),
                              );
                        },
                        title: appLocalizationsOf(context).skipEmphasized,
                      ),
                  ],
                );
              }
              if (state is FsEntryMoveLoadSuccess) {
                final globalHideBloc = context.read<GlobalHideBloc>();

                final List<FolderEntry> subFolders;
                if (globalHideBloc.state is ShowingHiddenItems) {
                  subFolders = state.viewingFolder.subfolders;
                } else {
                  subFolders = state.viewingFolder.subfolders
                      .where((f) => !f.isHidden)
                      .toList();
                }

                final items = [
                  ...subFolders.map(
                    (f) {
                      final enabled = state.itemsToMove
                          .where((item) => item.id == f.id)
                          .isEmpty;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16.0, horizontal: 16),
                        child: GestureDetector(
                          onTap: enabled
                              ? () {
                                  context.read<FsEntryMoveBloc>().add(
                                        FsEntryMoveUpdateTargetFolder(
                                          folderId: f.id,
                                        ),
                                      );
                                }
                              : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ArDriveIcons.folderOutline(
                                size: 16,
                                color: enabled ? null : _colorDisabled(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  f.name,
                                  style: typography.paragraphNormal().copyWith(
                                        color: enabled
                                            ? null
                                            : _colorDisabled(context),
                                      ),
                                ),
                              ),
                              ArDriveIcons.carretRight(
                                size: 18,
                                color: enabled ? null : _colorDisabled(context),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  ...state.viewingFolder.files.map(
                    (f) => Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16.0,
                        horizontal: 16,
                      ),
                      child: Row(
                        children: [
                          ArDriveIcons.fileOutlined(
                            size: 16,
                            color: _colorDisabled(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f.name,
                              style: typography.paragraphNormal().copyWith(
                                    color: _colorDisabled(context),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ];

                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ArDriveCard(
                    height: 441,
                    width: kMediumDialogWidth,
                    contentPadding: EdgeInsets.zero,
                    content: SizedBox(
                      height: 325,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.only(left: 16, right: 16),
                            width: double.infinity,
                            height: 77,
                            alignment: Alignment.centerLeft,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeBgCanvas,
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  width: !state.viewingRootFolder ? 20 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: GestureDetector(
                                    onTap: () {
                                      context.read<FsEntryMoveBloc>().add(
                                            FsEntryMoveGoBackToParent(
                                              folderInView:
                                                  state.viewingFolder.folder,
                                            ),
                                          );
                                    },
                                    child: AnimatedScale(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      scale: !state.viewingRootFolder ? 1 : 0,
                                      child: ArDriveIcons.arrowLeft(
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),
                                AnimatedPadding(
                                  duration: const Duration(milliseconds: 200),
                                  padding: !state.viewingRootFolder
                                      ? const EdgeInsets.only(left: 8)
                                      : const EdgeInsets.only(left: 0),
                                  child: Text(
                                    appLocalizationsOf(context).moveItems,
                                    style: typography.paragraphXLarge(
                                      fontWeight: ArFontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                  child: ArDriveIcons.x(
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                return items[index];
                              },
                            ),
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Flexible(
                                child: ArDriveButtonNew(
                                  typography: typography,
                                  maxHeight: 36,
                                  maxWidth: 200,
                                  variant: ButtonVariant.secondary,
                                  text: appLocalizationsOf(context)
                                      .createFolderEmphasized,
                                  content: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        ArDriveIcons.iconNewFolder1(),
                                        const SizedBox(width: 8),
                                        Text(
                                          appLocalizationsOf(context)
                                              .createFolderEmphasized,
                                          style: typography.paragraphNormal(
                                            fontWeight: ArFontWeight.semiBold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  onPressed: () {
                                    showArDriveDialog(
                                      context,
                                      content: BlocProvider(
                                        create: (context) => FolderCreateCubit(
                                          driveId: state
                                              .viewingFolder.folder.driveId,
                                          parentFolderId:
                                              state.viewingFolder.folder.id,
                                          profileCubit:
                                              context.read<ProfileCubit>(),
                                          arweave:
                                              context.read<ArweaveService>(),
                                          turboUploadService: context
                                              .read<TurboUploadService>(),
                                          driveDao: context.read<DriveDao>(),
                                        ),
                                        child: const FolderCreateForm(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Flexible(
                                child: ArDriveButtonNew(
                                  typography: typography,
                                  maxHeight: 36,
                                  maxWidth: 150,
                                  variant: ButtonVariant.primary,
                                  text: appLocalizationsOf(context)
                                      .moveHereEmphasized,
                                  onPressed: () {
                                    context.read<FsEntryMoveBloc>().add(
                                          FsEntryMoveSubmit(
                                            folderInView:
                                                state.viewingFolder.folder,
                                            showHiddenItems: globalHideBloc
                                                .state is ShowingHiddenItems,
                                          ),
                                        );
                                    context
                                        .read<DriveDetailCubit>()
                                        .forceDisableMultiselect = true;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                );
              } else {
                return const SizedBox();
              }
            });
          },
        );
      },
    );
  }

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colors.themeInputPlaceholder;
}
