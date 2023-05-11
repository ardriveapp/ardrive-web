import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/add_debounce.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> attachDrive({
  required BuildContext context,
  DriveID? driveId,
  String? driveName,
  SecretKey? driveKey,
}) {
  final profileState = context.read<ProfileCubit>().state;
  final profileKey =
      profileState is ProfileLoggedIn ? profileState.cipherKey : null;
  return showModalDialog(
    context,
    () => showAnimatedDialog(
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
  const DriveAttachForm({Key? key}) : super(key: key);

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
          showAnimatedDialog(
            context,
            content: ArDriveStandardModal(
              title: appLocalizationsOf(context).error,
              description: appLocalizationsOf(context).invalidKeyFile,
            ),
          );
        } else if (state is DriveAttachDriveNotFound) {
          showAnimatedDialog(
            context,
            content: ArDriveStandardModal(
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
            title: appLocalizationsOf(context).attachingDriveEmphasized,
          );
        }

        return ArDriveStandardModal(
          title: appLocalizationsOf(context).attachDriveEmphasized,
          content: SizedBox(
            width: kMediumDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArDriveTextField(
                  controller:
                      context.read<DriveAttachCubit>().driveIdController,
                  autofocus: true,
                  onChanged: (s) async {
                    await context.read<DriveAttachCubit>().drivePrivacyLoader();

                    // ignore: use_build_context_synchronously
                    if (context.read<DriveAttachCubit>().state
                        is! DriveAttachPrivate) {
                      debounce(() {
                        context.read<DriveAttachCubit>().driveNameLoader();
                      });
                    }
                  },
                  hintText: appLocalizationsOf(context).driveID,
                ),
                const SizedBox(height: 16),
                if (state is DriveAttachPrivate)
                  ArDriveTextField(
                    controller:
                        context.read<DriveAttachCubit>().driveKeyController,
                    autofocus: true,
                    obscureText: true,
                    onChanged: (s) async {},
                    validator: (s) async {
                      final cubit = context.read<DriveAttachCubit>();

                      final validation = await cubit.driveKeyValidator();

                      return validation;
                    },
                    hintText: appLocalizationsOf(context).driveKey,
                  ),
                const SizedBox(height: 16),
                ArDriveTextField(
                  controller:
                      context.read<DriveAttachCubit>().driveNameController,
                  hintText: appLocalizationsOf(context).driveName,
                  onChanged: (s) async {},
                  validator: (s) async {
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
