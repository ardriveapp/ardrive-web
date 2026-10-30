import 'package:ardrive/components/password_autofill.dart';
import 'package:ardrive/components/reactive_select_field.dart';
import 'package:ardrive/authentication/login/views/modals/common.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/components/turbo_payment_required_dialog.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToCreateDrive(
  BuildContext context, {
  DrivePrivacy? privacy,
}) =>
    showArDriveDialog(
      context,
      content: BlocProvider(
        create: (_) => DriveCreateCubit(
          privacy: privacy ?? DrivePrivacy.private,
          arweave: context.read<ArweaveService>(),
          turboUploadService: context.read<TurboUploadService>(),
          driveDao: context.read<DriveDao>(),
          profileCubit: context.read<ProfileCubit>(),
          drivesCubit: context.read<DrivesCubit>(),
          driveUnlocker: context.read<DriveUnlocker>(),
        ),
        child: const DriveCreateForm(),
      ),
    );

class DriveCreateForm extends StatefulWidget {
  const DriveCreateForm({super.key});

  @override
  State<DriveCreateForm> createState() => _DriveCreateFormState();
}

class _DriveCreateFormState extends State<DriveCreateForm> {
  final _driveNameController = TextEditingController();
  bool _isDriveNameValid = false;

  // The drive password, when the sign-in one isn't proven - see
  // [DriveCreateCubit.needsDrivePassword]. An existing password, checked by
  // opening one of the user's drives, so no confirmation and no rules.
  final _drivePassword = TextEditingController();
  final _drivePasswordFocus = FocusNode(debugLabel: 'drivePassword');
  bool _checking = false;

  // Typing again clears what the last check said.
  bool _rejectionSeen = false;

  Future<void> _create(DriveCreateCubit cubit) async {
    if (!cubit.needsDrivePassword) {
      await cubit.submit(_driveNameController.text);
      return;
    }

    setState(() {
      _checking = true;
      _rejectionSeen = false;
    });
    try {
      await cubit.submit(_driveNameController.text,
          drivePassword: _drivePassword.text);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String? _drivePasswordError(BuildContext context, DriveCreateState state) {
    if (state is! DriveCreateDrivePasswordRejected || _rejectionSeen) {
      return null;
    }
    final s = appLocalizationsOf(context);
    return switch (state.reason) {
      DriveUnlockFailure.wrongPassword => s.drivePasswordOpensNoDrives,
      DriveUnlockFailure.walletFailed => s.unlockWalletFailed,
      _ => s.unlockNetworkError,
    };
  }

  @override
  void dispose() {
    _drivePassword.dispose();
    _drivePasswordFocus.dispose();
    super.dispose();
  }

  /// The drive password, with the wallet address as the username, so a
  /// browser offers to save it for this account and fill it next time.
  Widget _withAutofill(BuildContext context, Widget field) {
    final ProfileState profile;
    try {
      profile = context.read<ProfileCubit>().state;
    } on ProviderNotFoundException {
      return field;
    }
    if (profile is! ProfileLoggedIn) return field;
    return PasswordAutofillGroup(
      username: profile.user.walletAddress,
      child: field,
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DriveCreateCubit, DriveCreateState>(
        listener: (context, state) {
          if (state is DriveCreateDrivePasswordRejected) {
            // Back to the field, its text selected, so the next attempt is
            // typed straight over the last.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _drivePasswordFocus.requestFocus();
              _drivePassword.selection = TextSelection(
                  baseOffset: 0, extentOffset: _drivePassword.text.length);
            });
          } else if (state is DriveCreateInProgress) {
            showProgressDialog(
              context,
              title: appLocalizationsOf(context).creatingDriveEmphasized,
            );
          } else if (state is DriveCreateSuccess) {
            // The drive password worked: the browser may save it.
            if (_drivePassword.text.isNotEmpty) PasswordAutofillGroup.save();
            Navigator.pop(context);
            Navigator.pop(context);
            PlausibleEventTracker.trackDriveCreation(
              drivePrivacy: state.privacy,
            );
          } else if (state is DriveCreateWalletMismatch) {
            Navigator.pop(context);
          } else if (state is DriveCreateFailure) {
            Navigator.pop(context);
            if (state.isPaymentError) {
              showTurboPaymentRequiredDialog(context);
            } else {
              showErrorDialog(
                context: context,
                title: appLocalizationsOf(context).error,
                message:
                    'There was a problem creating this drive.\nPlease try again later.',
              );
            }
          }
        },
        builder: (context, state) {
          if (state is DriveCreateZeroBalance) {
            // Cancel was the only way out of this, which made the whole
            // path a dead end: no AR, no Credits, no drive, no next step.
            // The same offer every other payment refusal makes - see
            // [showTurboPaymentRequiredDialog].
            return ArDriveStandardModalNew(
              title: appLocalizationsOf(context).createDriveEmphasized,
              description:
                  appLocalizationsOf(context).insufficientARToCreateDrive,
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(),
                  title: appLocalizationsOf(context).cancelEmphasized,
                ),
                ModalAction(
                  action: () {
                    Navigator.of(context).pop();
                    showTurboTopupModal(context);
                  },
                  title: appLocalizationsOf(context).buyCredits,
                ),
              ],
            );
          } else {
            final privacy = state.privacy;
            final typography = ArDriveTypographyNew.of(context);
            final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
            final cubit = context.read<DriveCreateCubit>();
            final needsPassword = cubit.needsDrivePassword;

            return ArDriveStandardModalNew(
              title: appLocalizationsOf(context).createDriveEmphasized,
              content: SizedBox(
                width: kMediumDialogWidth,
                child: ReactiveForm(
                  formGroup: context.watch<DriveCreateCubit>().form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArDriveTextFieldNew(
                        controller: _driveNameController,
                        autofocus: true,
                        onFieldSubmitted: (value) {
                          if (_isDriveNameValid) {
                            context
                                .read<FolderCreateCubit>()
                                .submit(folderName: value);
                          }
                        },
                        hintText: appLocalizationsOf(context).driveName,
                        validator: (value) {
                          final validation = validateEntityName(value, context);

                          if (validation == null) {
                            setState(() => _isDriveNameValid = true);
                          } else {
                            setState(() => _isDriveNameValid = false);
                          }

                          return validation;
                        },
                      ),
                      const SizedBox(height: 16),
                      ReactiveArDriveSelectField<String>(
                        formControlName: 'privacy',
                        label: appLocalizationsOf(context).privacy,
                        showErrors: (control) =>
                            control.dirty && control.invalid,
                        validationMessages:
                            kValidationMessages(appLocalizationsOf(context)),
                        choices: [
                          ArDriveChoice(
                            value: DrivePrivacy.public.name,
                            label: appLocalizationsOf(context).public,
                          ),
                          ArDriveChoice(
                            value: DrivePrivacy.private.name,
                            label: appLocalizationsOf(context).private,
                          ),
                        ],
                        onChanged: (_) {
                          context.read<DriveCreateCubit>().onPrivacyChanged();
                        },
                      ),
                      if (needsPassword) ...[
                        const SizedBox(height: 16),
                        _withAutofill(
                          context,
                          ArDriveTextFieldNew(
                            key: const Key('drivePassword'),
                            controller: _drivePassword,
                            focusNode: _drivePasswordFocus,
                            label: appLocalizationsOf(context)
                                .enterYourDrivePassword,
                            obscureText: true,
                            showObfuscationToggle: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [AutofillHints.password],
                            isEnabled: !_checking,
                            errorMessage: _drivePasswordError(context, state),
                            showErrorMessage:
                                _drivePasswordError(context, state) != null,
                            onChanged: (_) => setState(() {
                              _rejectionSeen = true;
                            }),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          if (privacy == DrivePrivacy.private)
                            Flexible(
                              child: Text(
                                appLocalizationsOf(context)
                                    .drivePrivacyDescriptionPrivate,
                                style: typography.paragraphNormal(
                                  color: colorTokens.textLow,
                                  fontWeight: ArFontWeight.semiBold,
                                ),
                              ),
                            )
                          else
                            Flexible(
                              child: Text(
                                appLocalizationsOf(context)
                                    .drivePrivacyDescriptionPublic,
                                style: typography.paragraphNormal(
                                  color: colorTokens.textLow,
                                  fontWeight: ArFontWeight.semiBold,
                                ),
                              ),
                            )
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                ModalAction(
                  action: () => Navigator.of(context).pop(),
                  title: appLocalizationsOf(context).cancelEmphasized,
                ),
                ModalAction(
                  isEnable: _isDriveNameValid &&
                      (!needsPassword || _drivePassword.text.isNotEmpty),
                  isLoading: _checking,
                  action: () => _create(cubit),
                  title: appLocalizationsOf(context).createDriveEmphasized,
                ),
              ],
            );
          }
        },
      );
}
