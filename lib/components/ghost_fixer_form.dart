import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/ghost_fixer/ghost_fixer_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import 'components.dart';

Future<void> promptToReCreateFolder(BuildContext context,
    {required FolderDataTableItem ghostFolder}) {
  if (ghostFolder.parentFolderId != null) {
    final driveDetailCubit = context.read<DriveDetailCubit>();
    return showArDriveDialog(
      context,
      content: BlocProvider(
        create: (context) => GhostFixerCubit(
          ghostFolder: ghostFolder,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          turboUploadService: context.read<TurboUploadService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: GhostFixerForm(
          driveDetailCubit: driveDetailCubit,
        ),
      ),
    );
  } else {
    //TODO: Fix missing root folder;
    throw UnimplementedError();
  }
}

class GhostFixerForm extends StatefulWidget {
  const GhostFixerForm({
    super.key,
    required this.driveDetailCubit,
  });

  final DriveDetailCubit driveDetailCubit;

  @override
  State<GhostFixerForm> createState() => _GhostFixerFormState();
}

class _GhostFixerFormState extends State<GhostFixerForm> {
  final _folderNameController = TextEditingController();
  bool _isFolderNameValid = false;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<GhostFixerCubit, GhostFixerState>(
        listener: (context, state) {
          if (state is GhostFixerRepairInProgress) {
            showProgressDialog(
              context,
              title: appLocalizationsOf(context).recreatingFolderEmphasized,
            );
          } else if (state is GhostFixerSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
            widget.driveDetailCubit.refreshDriveDataTable();
          } else if (state is GhostFixerWalletMismatch) {
            Navigator.pop(context);
          } else if (state is GhostFixerNameConflict) {
            showStandardDialog(
              context,
              title: appLocalizationsOf(context).nameConflict,
              description: appLocalizationsOf(context)
                  .validationEntityNameAlreadyPresent,
            );
          }
        },
        builder: (context, state) {
          Widget buildButtonBar() => ButtonBar(
                children: [
                  ArDriveButton(
                    style: ArDriveButtonStyle.secondary,
                    maxHeight: 36,
                    onPressed: () => Navigator.pop(context),
                    text: appLocalizationsOf(context).cancelEmphasized,
                    fontStyle: ArDriveTypography.body.buttonNormalRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
                    ),
                  ),
                  ArDriveButton(
                    maxHeight: 36,
                    isDisabled: !_isFolderNameValid,
                    onPressed: () => context
                        .read<GhostFixerCubit>()
                        .submit(_folderNameController.text),
                    text: appLocalizationsOf(context).fixEmphasized,
                    fontStyle: ArDriveTypography.body.buttonNormalRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
                    ),
                  ),
                ],
              );
          Widget buildCreateFolderButton() {
            if (state is GhostFixerFolderLoadSuccess) {
              return ArDriveButton(
                maxHeight: 36,
                style: ArDriveButtonStyle.secondary,
                icon: ArDriveIcons.iconNewFolder1(),
                text: appLocalizationsOf(context).createFolderEmphasized,
                fontStyle: ArDriveTypography.body.buttonNormalRegular(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
                ),
                onPressed: () => promptToCreateFolderWithoutCongestionWarning(
                  context,
                  driveId: state.viewingFolder.folder.driveId,
                  parentFolderId: state.viewingFolder.folder.id,
                ),
              );
            } else {
              return Container();
            }
          }

          if (state is GhostFixerFolderLoadSuccess) {
            final items = [
              ...state.viewingFolder.subfolders.map(
                (f) {
                  final enabled = f.id != state.movingEntryId;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16.0, horizontal: 16),
                    child: GestureDetector(
                      onTap: enabled
                          ? () =>
                              context.read<GhostFixerCubit>().loadFolder(f.id)
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
                              style: ArDriveTypography.body.inputNormalRegular(
                                color: enabled ? null : _colorDisabled(context),
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

            return ArDriveStandardModal(
              width: 600,
              title: appLocalizationsOf(context).recreateFolderEmphasized,
              content: SizedBox(
                  height: 441,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ArDriveTextField(
                        controller: _folderNameController,
                        validator: (s) {
                          final validation = validateEntityName(s, context);

                          if (validation == null) {
                            _isFolderNameValid = true;
                          } else {
                            _isFolderNameValid = false;
                          }

                          setState(() {});

                          return validation;
                        },
                        hintText: appLocalizationsOf(context).folderName,
                      ),
                      const SizedBox(height: 16),
                      Text(appLocalizationsOf(context).targetFolderEmphasized),
                      const SizedBox(height: 16),
                      if (!state.viewingRootFolder)
                        AnimatedContainer(
                          width: !state.viewingRootFolder ? 100 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: GestureDetector(
                            onTap: () => context
                                .read<GhostFixerCubit>()
                                .loadParentFolder(),
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 200),
                              scale: !state.viewingRootFolder ? 1 : 0,
                              child: Row(children: [
                                ArDriveIconButton(
                                  icon: ArDriveIcons.arrowLeft(),
                                  size: 32,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      appLocalizationsOf(context).back,
                                      style: ArDriveTypography.body
                                          .inputNormalRegular(),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Scrollbar(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: items.length,
                              itemBuilder: (context, index) => items[index],
                            ),
                          ),
                        ),
                      ),
                      const Divider(),
                      Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: ScreenTypeLayout.builder(
                            desktop: (context) => Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                buildCreateFolderButton(),
                                buildButtonBar(),
                              ],
                            ),
                            mobile: (context) => Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                buildCreateFolderButton(),
                                buildButtonBar(),
                              ],
                            ),
                          )),
                    ],
                  )),
            );
          }
          return const SizedBox();
        },
      );

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colors.themeInputPlaceholder;
}
