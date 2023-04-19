import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../pages/drive_detail/drive_detail_page.dart';
import 'components.dart';

Future<void> promptToMove(
  BuildContext context, {
  required String driveId,
  required List<ArDriveDataTableItem> selectedItems,
}) {
  return showAnimatedDialog(
    context,
    content: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => FsEntryMoveBloc(
            crypto: ArDriveCrypto(),
            driveId: driveId,
            selectedItems: selectedItems,
            arweave: context.read<ArweaveService>(),
            turboService: context.read<TurboService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
            syncCubit: context.read<SyncCubit>(),
          )..add(const FsEntryMoveInitial()),
        ),
        BlocProvider.value(
          value: context.read<DriveDetailCubit>(),
        )
      ],
      child: const FsEntryMoveForm(),
    ),
  );
}

class FsEntryMoveForm extends StatelessWidget {
  const FsEntryMoveForm({Key? key}) : super(key: key);

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
        return Builder(builder: (context) {
          if (state is FsEntryMoveNameConflict) {
            return ArDriveStandardModal(
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
                            ),
                          );
                    },
                    title: appLocalizationsOf(context).skipEmphasized,
                  ),
              ],
            );
          }
          if (state is FsEntryMoveLoadSuccess) {
            final items = [
              ...state.viewingFolder.subfolders.map(
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
                        children: [
                          ArDriveIcons.folderOutlined(
                            size: 16,
                            color: enabled ? null : _colorDisabled(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f.name,
                              style: ArDriveTypography.body.inputNormalRegular(
                                color: enabled ? null : _colorDisabled(context),
                              ),
                            ),
                          ),
                          ArDriveIcons.chevronRight(
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
                          style: ArDriveTypography.body.inputNormalRegular(
                            color: _colorDisabled(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ];

            return ArDriveCard(
              height: 441,
              contentPadding: EdgeInsets.zero,
              width: kMediumDialogWidth,
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
                                duration: const Duration(milliseconds: 200),
                                scale: !state.viewingRootFolder ? 1 : 0,
                                child: ArDriveIcons.arrowBack(
                                  size: 20,
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
                              style: ArDriveTypography.headline.headline5Bold(),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                            },
                            child: ArDriveIcons.closeIcon(
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
                    Container(
                      decoration: BoxDecoration(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeBgSurface,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ArDriveButton(
                              maxHeight: 36,
                              style: ArDriveButtonStyle.secondary,
                              backgroundColor: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                              fontStyle:
                                  ArDriveTypography.body.buttonNormalRegular(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgDefault,
                              ),
                              icon: ArDriveIcons.folderAdd(),
                              text: appLocalizationsOf(context)
                                  .createFolderEmphasized,
                              onPressed: () {
                                showAnimatedDialog(
                                  context,
                                  content: BlocProvider(
                                    create: (context) => FolderCreateCubit(
                                      driveId:
                                          state.viewingFolder.folder.driveId,
                                      parentFolderId:
                                          state.viewingFolder.folder.id,
                                      profileCubit:
                                          context.read<ProfileCubit>(),
                                      arweave: context.read<ArweaveService>(),
                                      turboService:
                                          context.read<TurboService>(),
                                      driveDao: context.read<DriveDao>(),
                                    ),
                                    child: const FolderCreateForm(),
                                  ),
                                );
                              }),
                          ArDriveButton(
                            maxHeight: 36,
                            backgroundColor: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                            fontStyle:
                                ArDriveTypography.body.buttonNormalRegular(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeAccentSubtle,
                            ),
                            text:
                                appLocalizationsOf(context).moveHereEmphasized,
                            onPressed: () {
                              context.read<FsEntryMoveBloc>().add(
                                    FsEntryMoveSubmit(
                                      folderInView: state.viewingFolder.folder,
                                    ),
                                  );
                              context
                                  .read<DriveDetailCubit>()
                                  .forceDisableMultiselect = true;
                            },
                          ),
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

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colors.themeInputPlaceholder;
}
