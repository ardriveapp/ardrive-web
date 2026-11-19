import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/payment_required_notice.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToCreateFolder(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
}) =>
    showArDriveDialog(
      context,
      barrierDismissible: false,
      content: BlocProvider(
        create: (context) => FolderCreateCubit(
          driveId: driveId,
          parentFolderId: parentFolderId,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          turboUploadService: context.read<TurboUploadService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: const FolderCreateForm(),
      ),
    );

/// The create folder step of a picker: [FolderCreateForm] with its own cubit,
/// drawn in place of the picker's list, so no dialog opens over the picker.
/// [onClose] goes back to the list, after a folder is made or on Cancel.
Widget folderCreateStep(
  BuildContext context, {
  required String driveId,
  required String parentFolderId,
  required VoidCallback onClose,
}) =>
    BlocProvider(
      create: (context) => FolderCreateCubit(
        driveId: driveId,
        parentFolderId: parentFolderId,
        profileCubit: context.read<ProfileCubit>(),
        arweave: context.read<ArweaveService>(),
        turboUploadService: context.read<TurboUploadService>(),
        driveDao: context.read<DriveDao>(),
      ),
      child: FolderCreateForm(onClose: onClose),
    );

/// The create folder dialog. A picker that makes a folder shows it in its own
/// dialog, in place of its list, with [onClose] to go back to the list;
/// without [onClose] it is a dialog of its own and closes itself.
class FolderCreateForm extends StatefulWidget {
  const FolderCreateForm({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  State<FolderCreateForm> createState() => _FolderCreateFormState();
}

class _FolderCreateFormState extends State<FolderCreateForm> {
  final TextEditingController _folderNameController = TextEditingController();

  bool _isFolderNameValid = false;

  /// Between the click and the answer, so a second click does nothing.
  bool _submitting = false;

  /// The name another entry in the folder already has, until the name changes.
  String? _takenName;

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _folderNameController.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext context, String folderName) async {
    if (_submitting || !_isFolderNameValid) return;
    setState(() {
      _submitting = true;
      _takenName = null;
    });
    try {
      await context.read<FolderCreateCubit>().submit(folderName: folderName);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FolderCreateCubit, FolderCreateState>(
        listener: (context, state) {
          if (state is FolderCreateSuccess) {
            _close();
          } else if (state is FolderCreateWalletMismatch) {
            Navigator.pop(context);
          } else if (state is FolderCreateNameAlreadyExists) {
            setState(() => _takenName = state.folderName);
          }
        },
        builder: (context, state) {
          final l10n = appLocalizationsOf(context);
          final busy = _submitting || state is FolderCreateInProgress;
          return ArDriveStandardModalNew(
            title: l10n.createFolderEmphasized,
            content: SizedBox(
              width: kMediumDialogWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ArDriveTextFieldNew(
                    controller: _folderNameController,
                    label: l10n.name,
                    autofocus: true,
                    isEnabled: !busy,
                    onChanged: (_) {
                      if (_takenName != null) {
                        setState(() => _takenName = null);
                      }
                    },
                    onFieldSubmitted: (value) {
                      if (_isFolderNameValid && !busy) {
                        _submit(context, value);
                      }
                    },
                    validator: (value) {
                      final validation = validateEntityName(value, context);

                      if (validation == null) {
                        setState(() => _isFolderNameValid = true);
                      } else {
                        setState(() => _isFolderNameValid = false);
                      }

                      return validation;
                    },
                  ),
                  if (_takenName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: ArDriveSpacing.md),
                      child: ArDriveNotice(
                        type: ArDriveNoticeType.error,
                        message: l10n.nameAlreadyExistsHere(_takenName!),
                      ),
                    ),
                  if (state is FolderCreateFailure)
                    Padding(
                      padding: const EdgeInsets.only(top: ArDriveSpacing.md),
                      child: state.isPaymentError
                          ? const PaymentRequiredNotice()
                          : ArDriveNotice(
                              type: ArDriveNoticeType.error,
                              title: l10n.couldNotCreateFolderTitle,
                              message: l10n.actionFailedTryAgain,
                              actionLabel: l10n.tryAgain,
                              onAction: _isFolderNameValid && !busy
                                  ? () => _submit(
                                      context, _folderNameController.text)
                                  : null,
                            ),
                    ),
                ],
              ),
            ),
            actions: [
              ModalAction.close(
                action: _close,
                title: l10n.cancelEmphasized,
                isEnable: !busy,
              ),
              ModalAction(
                isEnable: _isFolderNameValid,
                isLoading: busy,
                action: () => _submit(context, _folderNameController.text),
                title: l10n.createFolderEmphasized,
              ),
            ],
          );
        },
      );
}
