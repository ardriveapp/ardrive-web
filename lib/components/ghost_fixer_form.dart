import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/turbo_payment_required_dialog.dart';
import 'package:ardrive/blocs/ghost_fixer/ghost_fixer_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
          } else if (state is GhostFixerFailure) {
            Navigator.pop(context);
            if (state.isPaymentError) {
              showTurboPaymentRequiredDialog(context);
            } else {
              showArDriveDialog(
                context,
                content: ArDriveStandardModalNew(
                  title: appLocalizationsOf(context).error,
                  description: appLocalizationsOf(context).actionFailedTryAgain,
                ),
              );
            }
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
          if (state is! GhostFixerFolderLoadSuccess) {
            return const SizedBox();
          }

          final typography = ArDriveTypographyNew.of(context);
          final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
          final screen = MediaQuery.sizeOf(context);
          TextStyle rowStyle({required bool enabled}) =>
              typography.paragraphLarge(
                color: enabled ? colorTokens.textHigh : _colorDisabled(context),
              );

          final items = [
            ...state.viewingFolder.subfolders.map(
              (f) {
                final enabled = f.id != state.movingEntryId;
                return ArDriveClickArea(
                  showCursor: enabled,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: enabled
                        ? () => context.read<GhostFixerCubit>().loadFolder(f.id)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: ArDriveSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          ArDriveIcons.folderOutline(
                            size: 16,
                            color: enabled
                                ? colorTokens.iconMid
                                : _colorDisabled(context),
                          ),
                          const SizedBox(width: ArDriveSpacing.xs),
                          Expanded(
                            child:
                                Text(f.name, style: rowStyle(enabled: enabled)),
                          ),
                          ArDriveIcons.carretRight(
                            size: 18,
                            color: enabled
                                ? colorTokens.iconMid
                                : _colorDisabled(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            ...state.viewingFolder.files.map(
              (f) => Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: ArDriveSpacing.sm),
                child: Row(
                  children: [
                    ArDriveIcons.fileOutlined(
                      size: 16,
                      color: _colorDisabled(context),
                    ),
                    const SizedBox(width: ArDriveSpacing.xs),
                    Expanded(
                      child: Text(f.name, style: rowStyle(enabled: false)),
                    ),
                  ],
                ),
              ),
            ),
          ];

          return ArDriveStandardModalNew(
            // As wide as a large dialog, and no wider than the screen.
            width: screen.width < kLargeDialogWidth + 32
                ? screen.width - 32
                : kLargeDialogWidth,
            title: appLocalizationsOf(context).recreateFolderEmphasized,
            content: SizedBox(
              height: screen.height < 800 ? screen.height * 0.5 : 441,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ArDriveTextFieldNew(
                    controller: _folderNameController,
                    hintText: appLocalizationsOf(context).folderName,
                    validator: (s) {
                      final validation = validateEntityName(s, context);
                      setState(() => _isFolderNameValid = validation == null);
                      return validation;
                    },
                  ),
                  const SizedBox(height: ArDriveSpacing.md),
                  Text(
                    appLocalizationsOf(context).targetFolderEmphasized,
                    style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                  const SizedBox(height: ArDriveSpacing.xs),
                  if (!state.viewingRootFolder)
                    ArDriveClickArea(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            context.read<GhostFixerCubit>().loadParentFolder(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: ArDriveSpacing.xs,
                          ),
                          child: Row(children: [
                            ArDriveIcons.arrowLeft(
                              size: 18,
                              color: colorTokens.iconMid,
                            ),
                            const SizedBox(width: ArDriveSpacing.xs),
                            Text(
                              appLocalizationsOf(context).back,
                              style: rowStyle(enabled: true),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  Expanded(
                    child: ArDriveScrollBar(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) => items[index],
                      ),
                    ),
                  ),
                  Divider(color: colorTokens.strokeLow, height: 1),
                  const SizedBox(height: ArDriveSpacing.sm),
                  ArDriveButtonNew(
                    variant: ButtonVariant.outline,
                    size: ArDriveButtonSize.compact,
                    typography: typography,
                    icon: ArDriveIcons.iconNewFolder1(
                      size: 16,
                      color: colorTokens.textLink,
                    ),
                    text: appLocalizationsOf(context).createFolderEmphasized,
                    onPressed: () =>
                        promptToCreateFolderWithoutCongestionWarning(
                      context,
                      driveId: state.viewingFolder.folder.driveId,
                      parentFolderId: state.viewingFolder.folder.id,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              ModalAction.dismiss(
                action: () => Navigator.pop(context),
                title: appLocalizationsOf(context).cancelEmphasized,
              ),
              ModalAction(
                isEnable: _isFolderNameValid,
                action: () => context
                    .read<GhostFixerCubit>()
                    .submit(_folderNameController.text),
                title: appLocalizationsOf(context).fixEmphasized,
              ),
            ],
          );
        },
      );

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colorTokens.textXLow;
}
