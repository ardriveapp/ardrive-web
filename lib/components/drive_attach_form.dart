import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../utils/show_general_dialog.dart';
import 'components.dart';

Future<void> attachDrive({
  required BuildContext context,
  DriveID? driveId,
  String? driveName,
  DriveKey? driveKey,
}) {
  final profileState = context.read<ProfileCubit>().state;
  final profileKey =
      profileState is ProfileLoggedIn ? profileState.user.cipherKey : null;
  return showModalDialog(
    context,
    () => showArDriveDialog(
      context,
      content: BlocProvider<DriveAttachCubit>(
        create: (context) => DriveAttachCubit(
          initialDriveId: driveId,
          initialDriveName: driveName,
          initialDriveKey: driveKey,
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
          syncBloc: context.read<SyncCubit>(),
          drivesBloc: context.read<DrivesCubit>(),
          profileKey: profileKey,
        ),
        child: BlocListener<DriveAttachCubit, DriveAttachState>(
          listener: (context, state) {
            if (state is DriveAttachFailure || state is DriveAttachSuccess) {
              // Close the progress dialog if the drive attachment fails or succeeds.
              Navigator.pop(context);
            }
          },
          child: const DriveAttachForm(),
        ),
      ),
    ),
  );
}

/// Depends on a provided [DriveAttachCubit] for business logic.
class DriveAttachForm extends StatefulWidget {
  const DriveAttachForm({super.key});

  @override
  State<DriveAttachForm> createState() => _DriveAttachFormState();
}

class _DriveAttachFormState extends State<DriveAttachForm> {
  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<DriveAttachCubit>()
          .driveNameController
          .addListener(_onDriveNameChange);
    });
  }

  void _onDriveNameChange() {
    if (!mounted) {
      return;
    }

    setState(() {
      _isFormValid =
          context.read<DriveAttachCubit>().driveNameController.text.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DriveAttachCubit, DriveAttachState>(
      listener: (context, state) {
        if (state is DriveAttachInvalidDriveKey) {
          showArDriveDialog(
            context,
            content: ArDriveStandardModalNew(
              title: appLocalizationsOf(context).error,
              description: appLocalizationsOf(context).invalidKeyFile,
            ),
          );
        } else if (state is DriveAttachDriveNotFound) {
          showArDriveDialog(
            context,
            content: ArDriveStandardModalNew(
              title: appLocalizationsOf(context).error,
              description: appLocalizationsOf(context)
                  .validationAttachDriveCouldNotBeFound,
            ),
          );
        }
      },
      buildWhen: (previous, current) => current is! DriveAttachInvalidDriveKey,
      builder: (context, state) {
        if (state is DriveAttachInProgress) {
          return ProgressDialog(
            useNewArDriveUI: true,
            title: appLocalizationsOf(context).attachingDriveEmphasized,
          );
        }

        if (state is DriveAttachSyncing) {
          return ArDriveStandardModalNew(
            hasCloseButton: true,
            title: 'Syncing drive...',
            content: SizedBox(
              width: kMediumDialogWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(
                    state.hasSnapshots
                        ? 'Snapshots detected! Using optimized sync...\n\nThis should be quick!'
                        : 'Please wait while we sync the drive contents.\n\nThis may take a moment for large drives.',
                    textAlign: TextAlign.center,
                    style: ArDriveTypography.body.bodyRegular(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You can close this modal and continue using ArDrive.\nThe sync will continue in the background.',
                    textAlign: TextAlign.center,
                    style: ArDriveTypography.body.smallRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgSubtle,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ArDriveStandardModalNew(
          title: appLocalizationsOf(context).attachDriveEmphasized,
          content: SizedBox(
            width: kMediumDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArDriveTextFieldNew(
                  controller:
                      context.read<DriveAttachCubit>().driveIdController,
                  autofocus: true,
                  onChanged: (s) async {
                    await context.read<DriveAttachCubit>().drivePrivacyLoader();

                    // ignore: use_build_context_synchronously
                    if (context.read<DriveAttachCubit>().state
                        is! DriveAttachPrivate) {
                      debounce(() {
                        if (!mounted) {
                          logger.i(
                              'Drive attach form closed. Not loading drive name.');
                          return;
                        }

                        context.read<DriveAttachCubit>().driveNameLoader();
                      });
                    }
                  },
                  hintText: appLocalizationsOf(context).driveID,
                ),
                const SizedBox(height: 16),
                if (state is DriveAttachPrivate)
                  ArDriveTextFieldNew(
                    controller:
                        context.read<DriveAttachCubit>().driveKeyController,
                    autofocus: true,
                    obscureText: true,
                    onChanged: (s) async {},
                    asyncValidator: (s) async {
                      final cubit = context.read<DriveAttachCubit>();

                      final validation = await cubit.driveKeyValidator();

                      if (!mounted) {
                        logger.i(
                            'Drive attach form closed. Not validating drive key.');
                        return null;
                      }

                      return validation;
                    },
                    hintText: appLocalizationsOf(context).driveKey,
                  ),
                const SizedBox(height: 16),
                ArDriveTextFieldNew(
                  controller:
                      context.read<DriveAttachCubit>().driveNameController,
                  hintText: appLocalizationsOf(context).driveName,
                  onChanged: (s) async {},
                  asyncValidator: (s) async {
                    final nameValidation = validateEntityName(s, context);

                    setState(() {
                      _isFormValid = nameValidation == null;
                    });

                    return nameValidation;
                  },
                ),
              ],
            ),
          ),
          actions: [
            ModalAction(
              action: () => Navigator.of(context).pop(null),
              title: appLocalizationsOf(context).cancelEmphasized,
            ),
            ModalAction(
              isEnable: _isFormValid,
              action: () => context.read<DriveAttachCubit>().submit(),
              title: appLocalizationsOf(context).attachEmphasized,
            ),
          ],
        );
      },
    );
  }
}
