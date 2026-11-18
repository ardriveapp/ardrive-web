import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/turbo_payment_required_dialog.dart';
import 'package:ardrive/blocs/drive_rename/drive_rename_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> promptToRenameDrive(
  BuildContext context, {
  required String driveId,
  required String driveName,
}) =>
    showArDriveDialog(
      context,
      barrierDismissible: false,
      content: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => DriveRenameCubit(
              driveId: driveId,
              arweave: context.read<ArweaveService>(),
              turboUploadService: context.read<TurboUploadService>(),
              driveDao: context.read<DriveDao>(),
              profileCubit: context.read<ProfileCubit>(),
              syncCubit: context.read<SyncCubit>(),
            ),
          ),
          BlocProvider.value(
            value: context.read<DriveDetailCubit>(),
          ),
        ],
        child: DriveRenameForm(
          driveName: driveName,
        ),
      ),
    );

class DriveRenameForm extends StatefulWidget {
  const DriveRenameForm({
    super.key,
    required this.driveName,
  });

  final String driveName;

  @override
  State<DriveRenameForm> createState() => _DriveRenameFormState();
}

class _DriveRenameFormState extends State<DriveRenameForm> {
  bool _isFolderNameValid = false;
  final controller = TextEditingController();

  // The name another drive already has, said in the dialog with the choice to
  // rename anyway. Typing a different name clears it.
  String? _conflictingName;

  // The rename failed; the dialog stays open to try again.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    controller.text = widget.driveName;
    controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_conflictingName != null && controller.text != _conflictingName) {
      setState(() => _conflictingName = null);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit(BuildContext context, {bool proceedIfHasConflicts = false}) {
    setState(() => _failed = false);
    context.read<DriveRenameCubit>().submit(
          newName: controller.text,
          proceedIfHasConflicts: proceedIfHasConflicts,
        );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DriveRenameCubit, DriveRenameState>(
        listener: (context, state) {
          if (state is DriveRenameSuccess) {
            context.read<DriveDetailCubit>().refreshDriveDataTable();
            Navigator.pop(context);
          } else if (state is DriveRenameWalletMismatch) {
            Navigator.pop(context);
          } else if (state is DriveRenameFailure) {
            if (state.isPaymentError) {
              // Turbo wants Credits: the offer to buy them replaces this
              // dialog, the same as every other payment refusal.
              Navigator.pop(context);
              showTurboPaymentRequiredDialog(context);
            } else {
              setState(() => _failed = true);
            }
          } else if (state is DriveNameAlreadyExists) {
            setState(() {
              _conflictingName = state.driveName;
              _failed = false;
            });
          }
        },
        builder: (context, state) {
          final busy = state is DriveRenameInProgress;
          final conflict = _conflictingName != null;
          final l10n = appLocalizationsOf(context);

          return ArDriveStandardModalNew(
            title: l10n.renameDriveEmphasized,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ArDriveTextFieldNew(
                  controller: controller,
                  autofocus: true,
                  label: l10n.driveName,
                  isFieldRequired: true,
                  isEnabled: !busy,
                  validator: (value) {
                    if (value == widget.driveName) {
                      return l10n.validationNameUnchanged;
                    }

                    final validation = validateEntityName(value, context);

                    if (validation == null) {
                      setState(() => _isFolderNameValid = true);
                    } else {
                      setState(() => _isFolderNameValid = false);
                    }

                    return validation;
                  },
                ),
                if (conflict) ...[
                  const SizedBox(height: ArDriveSpacing.md),
                  ArDriveNotice(
                    type: ArDriveNoticeType.warning,
                    message: l10n.driveNameAlreadyExists,
                  ),
                ],
                if (_failed && !busy) ...[
                  const SizedBox(height: ArDriveSpacing.md),
                  ArDriveNotice(
                    type: ArDriveNoticeType.error,
                    message: l10n.actionFailedTryAgain,
                    actionLabel: l10n.tryAgain,
                    onAction: () =>
                        _submit(context, proceedIfHasConflicts: conflict),
                    onDismiss: () => setState(() => _failed = false),
                    dismissLabel: l10n.close,
                  ),
                ],
              ],
            ),
            actions: [
              ModalAction.close(
                action: () => Navigator.of(context).pop(),
                title: l10n.cancelEmphasized,
                isEnable: !busy,
              ),
              ModalAction(
                isEnable: _isFolderNameValid,
                isLoading: busy,
                action: () => _submit(context, proceedIfHasConflicts: conflict),
                title: conflict ? l10n.renameAnyway : l10n.renameEmphasized,
              ),
            ],
          );
        },
      );
}
