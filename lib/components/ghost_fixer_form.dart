import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/folder_picker_body.dart';
import 'package:ardrive/components/payment_required_notice.dart';
import 'package:ardrive/blocs/ghost_fixer/ghost_fixer_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
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
      barrierDismissible: false,
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

  /// The folder in view, kept while the cubit is busy, failed or found the
  /// name taken, so the dialog stays as it was and says so in itself.
  GhostFixerFolderLoadSuccess? _viewing;

  /// The name the target folder already has, until the name or folder changes.
  bool _nameTaken = false;

  /// The failure, kept until the next try, an edit or a move to another
  /// folder: the folder list can update under it.
  GhostFixerFailure? _failure;

  /// Making a folder in the target, in place of the list.
  bool _creatingFolder = false;

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }

  /// Set before the cubit is asked, cleared when it answers: the cubit checks
  /// the wallet and the name before it reports it is busy, so a quick second
  /// press would otherwise recreate the folder twice.
  bool _inFlight = false;

  Future<void> _submit(BuildContext context) async {
    if (_inFlight || !_isFolderNameValid) return;
    final cubit = context.read<GhostFixerCubit>();
    setState(() {
      _nameTaken = false;
      _failure = null;
      _inFlight = true;
    });
    try {
      await cubit.submit(_folderNameController.text);
    } finally {
      if (mounted) setState(() => _inFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<GhostFixerCubit, GhostFixerState>(
        listener: (context, state) {
          if (state is GhostFixerSuccess) {
            Navigator.pop(context);
            widget.driveDetailCubit.refreshDriveDataTable();
          } else if (state is GhostFixerWalletMismatch) {
            Navigator.pop(context);
          } else if (state is GhostFixerNameConflict) {
            setState(() => _nameTaken = true);
          } else if (state is GhostFixerFailure) {
            setState(() => _failure = state);
          }
        },
        builder: (context, state) {
          if (state is GhostFixerFolderLoadSuccess) {
            _viewing = state;
          }
          final viewing = _viewing;
          if (viewing == null) {
            return const SizedBox();
          }
          final l10n = appLocalizationsOf(context);

          if (_creatingFolder) {
            return folderCreateStep(
              context,
              driveId: viewing.viewingFolder.folder.driveId,
              parentFolderId: viewing.viewingFolder.folder.id,
              onClose: () => setState(() => _creatingFolder = false),
            );
          }

          final typography = ArDriveTypographyNew.of(context);
          final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
          final busy = _inFlight || state is GhostFixerRepairInProgress;
          final failure = _failure;

          return ArDriveStandardModalNew(
            width: folderPickerWidth(context),
            scrollableContent: true,
            title: l10n.recreateFolderEmphasized,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // First, so it is in view when the list is long.
                if (_nameTaken)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ArDriveSpacing.md),
                    child: ArDriveNotice(
                      type: ArDriveNoticeType.error,
                      title: l10n.nameConflict,
                      message: l10n.validationEntityNameAlreadyPresent,
                    ),
                  ),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ArDriveSpacing.md),
                    child: failure.isPaymentError
                        ? const PaymentRequiredNotice()
                        : ArDriveNotice(
                            type: ArDriveNoticeType.error,
                            title: l10n.couldNotRecreateFolderTitle,
                            message: l10n.actionFailedTryAgain,
                            actionLabel: l10n.tryAgain,
                            onAction: _isFolderNameValid && !busy
                                ? () => _submit(context)
                                : null,
                          ),
                  ),
                ArDriveTextFieldNew(
                  controller: _folderNameController,
                  label: l10n.folderName,
                  isEnabled: !busy,
                  onChanged: (_) {
                    if (_nameTaken || _failure != null) {
                      setState(() {
                        _nameTaken = false;
                        _failure = null;
                      });
                    }
                  },
                  validator: (s) {
                    final validation = validateEntityName(s, context);
                    setState(() => _isFolderNameValid = validation == null);
                    return validation;
                  },
                ),
                const SizedBox(height: ArDriveSpacing.md),
                Text(
                  l10n.targetFolderEmphasized,
                  style: typography.paragraphNormal(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
                const SizedBox(height: ArDriveSpacing.xs),
                FolderPickerBody(
                  folders: viewing.viewingFolder.subfolders,
                  fileNames:
                      viewing.viewingFolder.files.map((f) => f.name).toList(),
                  atRoot: viewing.viewingRootFolder,
                  enabled: !busy,
                  isFolderEnabled: (f) => f.id != viewing.movingEntryId,
                  onOpenFolder: (id) {
                    setState(() {
                      _nameTaken = false;
                      _failure = null;
                    });
                    context.read<GhostFixerCubit>().loadFolder(id);
                  },
                  onBack: () {
                    setState(() {
                      _nameTaken = false;
                      _failure = null;
                    });
                    context.read<GhostFixerCubit>().loadParentFolder();
                  },
                  onCreateFolder: () => setState(() => _creatingFolder = true),
                ),
              ],
            ),
            actions: [
              ModalAction.close(
                action: () => Navigator.pop(context),
                title: l10n.cancelEmphasized,
                isEnable: !busy,
              ),
              ModalAction(
                isEnable: _isFolderNameValid,
                isLoading: busy,
                action: () => _submit(context),
                title: l10n.recreateFolderEmphasized,
              ),
            ],
          );
        },
      );
}
