import 'package:ardrive/components/password_autofill.dart';
import 'package:ardrive/components/reactive_select_field.dart';
import 'package:ardrive/authentication/login/views/modals/common.dart';
import 'package:ardrive/authentication/password/breached_password.dart';
import 'package:ardrive/authentication/password/new_password.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
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
          unlockSession: context.read<DriveUnlockSession>(),
        ),
        child: const DriveCreateForm(),
      ),
    );

class DriveCreateForm extends StatefulWidget {
  const DriveCreateForm({super.key, this.breachCheck});

  /// Asks whether a typed drive password is in a known breach. Replaced in
  /// tests.
  final BreachedPasswordCheck? breachCheck;

  @override
  State<DriveCreateForm> createState() => _DriveCreateFormState();
}

class _DriveCreateFormState extends State<DriveCreateForm> {
  final _driveNameController = TextEditingController();
  bool _isDriveNameValid = false;

  // The drive's own password, when the sign-in one isn't proven - see
  // [DriveCreateCubit.needsDrivePassword]. The new-account rules apply.
  final _drivePassword = TextEditingController();
  final _confirmDrivePassword = TextEditingController();
  String? _breachedPassword;
  bool _checkingBreach = false;

  String? _drivePasswordError(BuildContext context) {
    final password = _drivePassword.text;
    if (password.isEmpty) return null;
    final s = appLocalizationsOf(context);
    if (password == _breachedPassword) return s.newPasswordBreached;
    return switch (assessNewPassword(password)) {
      PasswordStrength.tooShort => s.newPasswordTooShort,
      PasswordStrength.weak => s.newPasswordWeak,
      PasswordStrength.fair => s.newPasswordFair,
      PasswordStrength.strong => null,
    };
  }

  bool get _drivePasswordReady =>
      assessNewPassword(_drivePassword.text) == PasswordStrength.strong &&
      _drivePassword.text != _breachedPassword &&
      _drivePassword.text == _confirmDrivePassword.text;

  Future<void> _create(DriveCreateCubit cubit) async {
    if (!cubit.needsDrivePassword) {
      await cubit.submit(_driveNameController.text);
      return;
    }

    final password = _drivePassword.text;
    setState(() => _checkingBreach = true);
    final breached = await (widget.breachCheck ?? BreachedPasswordCheck())
        .isBreached(password);
    if (!mounted) return;
    setState(() {
      _checkingBreach = false;
      if (breached == true) _breachedPassword = password;
    });
    if (breached == true) return;

    await cubit.submit(_driveNameController.text, drivePassword: password);
  }

  /// The new drive password and its confirmation, with the wallet address as
  /// the username, so a browser offers to save it for this account.
  Widget _withAutofill(BuildContext context, Widget fields) {
    final ProfileState profile;
    try {
      profile = context.read<ProfileCubit>().state;
    } on ProviderNotFoundException {
      return fields;
    }
    if (profile is! ProfileLoggedIn) return fields;
    return PasswordAutofillGroup(
      username: profile.user.walletAddress,
      child: fields,
    );
  }

  @override
  void dispose() {
    _drivePassword.dispose();
    _confirmDrivePassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<DriveCreateCubit, DriveCreateState>(
        listener: (context, state) {
          if (state is DriveCreateInProgress) {
            showProgressDialog(
              context,
              title: appLocalizationsOf(context).creatingDriveEmphasized,
            );
          } else if (state is DriveCreateSuccess) {
            // The new drive's own password worked: the browser may save it.
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
            final mismatch = _confirmDrivePassword.text.isNotEmpty &&
                _confirmDrivePassword.text != _drivePassword.text;

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
                        Text(
                          appLocalizationsOf(context).newDrivePasswordBody,
                          style: typography.paragraphNormal(
                              color: colorTokens.textMid),
                        ),
                        const SizedBox(height: 8),
                        _withAutofill(
                          context,
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ArDriveTextFieldNew(
                                key: const Key('newDrivePassword'),
                                controller: _drivePassword,
                                label: appLocalizationsOf(context)
                                    .drivePasswordLabel,
                                obscureText: true,
                                showObfuscationToggle: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [
                                  AutofillHints.newPassword
                                ],
                                errorMessage: _drivePasswordError(context),
                                showErrorMessage:
                                    _drivePasswordError(context) != null,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 8),
                              ArDriveTextFieldNew(
                                key: const Key('newDrivePasswordConfirm'),
                                controller: _confirmDrivePassword,
                                label:
                                    appLocalizationsOf(context).confirmPassword,
                                obscureText: true,
                                showObfuscationToggle: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [
                                  AutofillHints.newPassword
                                ],
                                errorMessage: mismatch
                                    ? appLocalizationsOf(context)
                                        .passwordDoNotMatch
                                    : null,
                                showErrorMessage: mismatch,
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
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
                      (!needsPassword || _drivePasswordReady),
                  isLoading: _checkingBreach,
                  action: () => _create(cubit),
                  title: appLocalizationsOf(context).createDriveEmphasized,
                ),
              ],
            );
          }
        },
      );
}
