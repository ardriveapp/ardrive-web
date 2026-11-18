import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/payment_required_notice.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void promptToRenameModal(
  BuildContext context, {
  required String driveId,
  String? folderId,
  String? fileId,
  required String initialName,
}) {
  showArDriveDialog(
    context,
    barrierDismissible: false,
    content: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => FsEntryRenameCubit(
            crypto: ArDriveCrypto(),
            driveId: driveId,
            folderId: folderId,
            fileId: fileId,
            arweave: context.read<ArweaveService>(),
            turboUploadService: context.read<TurboUploadService>(),
            driveDao: context.read<DriveDao>(),
            profileCubit: context.read<ProfileCubit>(),
          ),
        ),
        BlocProvider.value(
          value: context.read<DriveDetailCubit>(),
        ),
      ],
      child: FsEntryRenameForm(
        entryName: initialName,
      ),
    ),
  );
}

class FsEntryRenameForm extends StatefulWidget {
  const FsEntryRenameForm({
    super.key,
    required this.entryName,
  });

  final String entryName;

  @override
  State<FsEntryRenameForm> createState() => _FsEntryRenameFormState();
}

class _FsEntryRenameFormState extends State<FsEntryRenameForm> {
  final _nameController = TextEditingController();

  /// The name another entry in the folder already has, until the name changes.
  String? _takenName;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.entryName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool _validForm = false;

  /// Kept for Try again, so a retry does not ask about the extension twice.
  bool _updateExtension = false;

  /// The extension step's Rename was pressed: busy at once, so a quick second
  /// press cannot send it twice.
  bool _confirmingExtension = false;

  void _submit({bool? updateExtension}) {
    if (updateExtension != null) _updateExtension = updateExtension;
    setState(() => _takenName = null);
    context.read<FsEntryRenameCubit>().submit(
          newName: _nameController.text,
          updateExtension: _updateExtension,
        );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FsEntryRenameCubit, FsEntryRenameState>(
        listener: (context, state) {
          if (state is FolderEntryRenameSuccess ||
              state is FileEntryRenameSuccess) {
            context.read<DriveDetailCubit>().refreshDriveDataTable();

            Navigator.pop(context);
          } else if (state is FolderEntryRenameWalletMismatch ||
              state is FileEntryRenameWalletMismatch) {
            Navigator.pop(context);
          } else if (state is EntityAlreadyExists) {
            setState(() => _takenName = state.entityName);
          }
        },
        builder: (context, state) {
          final l10n = appLocalizationsOf(context);
          if (state is! UpdatingEntityExtension) _confirmingExtension = false;
          if (state is UpdatingEntityExtension) {
            return _extensionStep(context, state);
          }

          final busy = state is FolderEntryRenameInProgress ||
              state is FileEntryRenameInProgress;
          final failure = state is FolderEntryRenameFailure ||
              state is FileEntryRenameFailure;
          final paymentError =
              (state is FolderEntryRenameFailure && state.isPaymentError) ||
                  (state is FileEntryRenameFailure && state.isPaymentError);

          return ArDriveStandardModalNew(
            title: state.isRenamingFolder
                ? l10n.renameFolderEmphasized
                : l10n.renameFileEmphasized,
            content: state is! FsEntryRenameInitializing
                ? SizedBox(
                    width: kMediumDialogWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ArDriveTextFieldNew(
                          controller: _nameController,
                          label: l10n.name,
                          autofocus: true,
                          isEnabled: !busy,
                          onChanged: (_) {
                            _updateExtension = false;
                            if (_takenName != null) {
                              setState(() => _takenName = null);
                            }
                          },
                          onFieldSubmitted: (value) {
                            if (_validForm && !busy) {
                              _submit();
                            }
                          },
                          validator: (value) {
                            final validation =
                                validateEntityName(value, context);

                            if (validation == null) {
                              setState(() => _validForm = true);
                            } else {
                              setState(() => _validForm = false);
                            }

                            return validation;
                          },
                        ),
                        if (_takenName != null)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: ArDriveSpacing.md),
                            child: ArDriveNotice(
                              type: ArDriveNoticeType.error,
                              message: l10n.nameAlreadyExistsHere(_takenName!),
                            ),
                          ),
                        if (failure)
                          Padding(
                            padding:
                                const EdgeInsets.only(top: ArDriveSpacing.md),
                            child: paymentError
                                ? const PaymentRequiredNotice()
                                : ArDriveNotice(
                                    type: ArDriveNoticeType.error,
                                    title: l10n.couldNotRenameTitle,
                                    message: l10n.actionFailedTryAgain,
                                    actionLabel: l10n.tryAgain,
                                    onAction: _submit,
                                  ),
                          ),
                      ],
                    ),
                  )
                : Container(),
            actions: [
              ModalAction.close(
                action: () => Navigator.of(context).pop(),
                title: l10n.cancelEmphasized,
                isEnable: !busy,
              ),
              ModalAction(
                action: _submit,
                title: l10n.renameEmphasized,
                isEnable: _validForm,
                isLoading: busy,
              ),
            ],
          );
        },
      );

  /// A changed extension is confirmed in the same dialog: nothing else is
  /// asked of the name, so this replaces the form for one step.
  Widget _extensionStep(BuildContext context, UpdatingEntityExtension state) {
    final l10n = appLocalizationsOf(context);
    return ArDriveStandardModalNew(
      title: l10n.changeExtensionTitle,
      description: l10n.changeExtensionBody(
        state.previousExtension,
        getFileExtension(
          name: state.entityName,
          contentType: state.newExtension,
        ),
      ),
      actions: [
        ModalAction.dismiss(
          action: () => context.read<FsEntryRenameCubit>().reset(),
          title: l10n.back,
          isEnable: !_confirmingExtension,
        ),
        ModalAction(
          action: () {
            if (_confirmingExtension) return;
            setState(() => _confirmingExtension = true);
            _submit(updateExtension: true);
          },
          title: l10n.renameEmphasized,
          isLoading: _confirmingExtension,
        ),
      ],
    );
  }
}
