import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart';

Future<void> showPinFileDialog({
  required BuildContext context,
}) {
  final arweave = context.read<ArweaveService>();
  final driveDao = context.read<DriveDao>();
  final turboService = context.read<TurboUploadService>();
  final profileCubit = context.read<ProfileCubit>();
  final driveDetailCubit = context.read<DriveDetailCubit>();
  final ConfigService configService = context.read<ConfigService>();

  final stateAsLoggedIn = driveDetailCubit.state as DriveDetailLoadSuccess;
  final currentDrive = stateAsLoggedIn.currentDrive;
  final currentFolder = stateAsLoggedIn.folderInView;

  return showModalDialog(
    context,
    () => showAnimatedDialog(
      context,
      content: BlocProvider(
        create: (context) {
          final FileIdResolver fileIdResolver = NetworkFileIdResolver(
            arweave: arweave,
            httpClient: Client(),
            configService: configService,
          );
          return PinFileBloc(
            fileIdResolver: fileIdResolver,
            arweave: arweave,
            driveDao: driveDao,
            turboUploadService: turboService,
            profileCubit: profileCubit,
            driveID: currentDrive.id,
            parentFolderId: currentFolder.folder.id,
          );
        },
        child: const PinFileDialog(),
      ),
    ),
  );
}

class PinFileDialog extends StatelessWidget {
  const PinFileDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final pinFileBloc = context.read<PinFileBloc>();

    return BlocConsumer<PinFileBloc, PinFileState>(
      listener: (context, state) {
        logger.d('PinFileBloc state: $state');

        if (state is PinFileAbort || state is PinFileSuccess) {
          Navigator.of(context).pop();
        } else if (state is PinFileError) {
          // TODO: Localize
          const errorText = 'Your pin failed to upload';
          showAnimatedDialog(
            context,
            content: _errorDialog(
              context,
              errorText: errorText,
            ),
          );
        } else if (state is PinFileFieldsValidationError) {
          if (state.networkError) {
            // TODO: Localize
            const errorText = 'Failed to retrieve file information';
            showAnimatedDialog(
              context,
              content: _errorDialog(
                context,
                errorText: errorText,
              ),
            );
          }
        }
      },
      builder: (context, state) {
        String? customErrorMessage;

        if (state is PinFileError) {
          return const SizedBox();
        }

        if (state is PinFileFieldsValidationError) {
          if (!state.doesDataTransactionExist) {
            customErrorMessage =
                appLocalizationsOf(context).theIdProvidedDoesntExist;
          }
          // TODO: refactor the arweave method to let it distinguish between
          /// these other cases
          else if (!state.isArFsEntityValid) {
            customErrorMessage = 'The file does exist but is invalid';
          }
          // else if (!state.isArFsEntityPublic) {
          //   customErrorMessage = 'File is not public';
          // }
        }

        if (customErrorMessage == null) {
          if (state.nameValidation == NameValidationResult.conflicting) {
            customErrorMessage =
                appLocalizationsOf(context).conflictingNameFound;
          }
        }

        return ArDriveStandardModal(
          title: appLocalizationsOf(context).newFilePin,
          content: SizedBox(
            width: kMediumDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArDriveTextField(
                  isEnabled: state is! PinFileNetworkCheckRunning,
                  label: appLocalizationsOf(context).enterTxIdOrFileId,
                  isFieldRequired: true,
                  onChanged: (value) {
                    pinFileBloc.add(
                      FieldsChanged(id: value, name: state.name),
                    );
                  },
                  validator: (p0) {
                    if (p0 != null) {
                      final validation = pinFileBloc.validateId(p0);
                      if (validation == IdValidationResult.invalid) {
                        return appLocalizationsOf(context)
                            .theIdProvidedIsNotValid;
                      } else if (validation == IdValidationResult.required) {
                        return appLocalizationsOf(context).validationRequired;
                      }
                    }
                    return null;
                  },
                ),
                ArDriveTextField(
                  isEnabled: true,
                  label: appLocalizationsOf(context).enterFileName,
                  isFieldRequired: true,
                  onChanged: (value) {
                    pinFileBloc.add(
                      FieldsChanged(id: state.id, name: value),
                    );
                  },
                  validator: (p0) {
                    if (p0 != null) {
                      final validation = pinFileBloc.validateName(p0);
                      if (validation == NameValidationResult.invalid) {
                        return appLocalizationsOf(context).validationInvalid;
                      } else if (validation == NameValidationResult.required) {
                        return appLocalizationsOf(context).validationRequired;
                      }
                    }
                    return null;
                  },
                  controller: pinFileBloc.nameTextController,
                ),
                if (customErrorMessage != null)
                  SizedBox(
                    width: kMediumDialogWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          customErrorMessage,
                          style:
                              Theme.of(context).textTheme.labelLarge!.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                        ),
                      ),
                    ),
                  )
              ],
            ),
          ),
          actions: [
            ModalAction(
              action: () => pinFileBloc.add(const PinFileCancel()),
              title: appLocalizationsOf(context).cancel,
            ),
            ModalAction(
              action: () => pinFileBloc.add(const PinFileSubmit()),
              title: appLocalizationsOf(context).create,
              // FIXME: "isEnabled"
              isEnable: state is PinFileFieldsValid &&
                  state.nameValidation == NameValidationResult.valid,
            ),
          ],
        );
      },
    );
  }

  ArDriveStandardModal _errorDialog(
    BuildContext context, {
    required String errorText,
  }) =>
      ArDriveStandardModal(
        width: kMediumDialogWidth,
        title: appLocalizationsOf(context).error,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(errorText),
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          ModalAction(
            action: () => Navigator.pop(context),
            title: appLocalizationsOf(context).okEmphasized,
          ),
        ],
      );
}
