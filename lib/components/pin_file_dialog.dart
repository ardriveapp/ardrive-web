import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
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
    () => showArDriveDialog(
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
          showArDriveDialog(
            context,
            content: _errorDialog(
              context,
              errorText: appLocalizationsOf(context).pinFailedToUpload,
              doublePop: true,
            ),
          );
        } else if (state is PinFileFieldsValidationError) {
          if (state.networkError) {
            showArDriveDialog(
              context,
              content: _errorDialog(
                context,
                errorText:
                    appLocalizationsOf(context).failedToRetrieveFileInfromation,
                // FIXME: We've decided to force the user start over again
                /// In the future there's gonna be a retry button
                doublePop: true,
              ),
            );
          }
        }
      },
      builder: (context, state) {
        if (state is PinFileError) {
          return const SizedBox();
        }

        final idValidationError = _getIdValidationError(context, state);
        final nameValidationError = _getNameValidationError(context, state);

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
                  errorMessage: idValidationError,
                  showErrorMessage: idValidationError != null,
                  onChanged: (value) {
                    pinFileBloc.add(
                      FieldsChanged(id: value, name: state.name),
                    );
                  },
                ),
                ArDriveTextField(
                  isEnabled: true,
                  label: appLocalizationsOf(context).enterFileName,
                  isFieldRequired: true,
                  errorMessage: nameValidationError,
                  showErrorMessage: nameValidationError != null,
                  onChanged: (value) {
                    pinFileBloc.add(
                      FieldsChanged(id: state.id, name: value),
                    );
                  },
                  controller: pinFileBloc.nameTextController,
                ),
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

  String? _getIdValidationError(BuildContext context, PinFileState state) {
    // if (state is PinFileInitial) {
    //   return null;
    // }

    if (state.idValidation == IdValidationResult.invalid) {
      return appLocalizationsOf(context).theIdProvidedIsNotValid;
    } else if (state.idValidation == IdValidationResult.required) {
      return appLocalizationsOf(context).validationRequired;
    }

    if (state is PinFileFieldsValidationError) {
      if (state.networkError) {
        return appLocalizationsOf(context).failedToRetrieveFileInfromation;
      } else if (!state.doesDataTransactionExist) {
        return appLocalizationsOf(context).theIdProvidedDoesntExist;
      }
      // TODO: refactor the arweave method to let it distinguish between
      /// these other cases
      else if (!state.isArFsEntityValid) {
        return appLocalizationsOf(context).fileDoesExistButIsInvalid;
      } else if (!state.isArFsEntityPublic) {
        return appLocalizationsOf(context).fileIsNotPublic;
      }
    }

    return null;
  }

  String? _getNameValidationError(BuildContext context, PinFileState state) {
    // if (state is PinFileInitial) {
    //   return null;
    // }

    if (state.nameValidation == NameValidationResult.invalid) {
      return appLocalizationsOf(context).validationInvalid;
    } else if (state.nameValidation == NameValidationResult.required) {
      return appLocalizationsOf(context).validationRequired;
    } else if (state.nameValidation == NameValidationResult.conflicting) {
      return appLocalizationsOf(context).conflictingNameFound;
    }
    return null;
  }

  ArDriveStandardModal _errorDialog(
    BuildContext context, {
    required String errorText,
    bool doublePop = false,
  }) =>
      ArDriveStandardModal(
        width: kMediumDialogWidth,
        title: appLocalizationsOf(context).failedToCreatePin,
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
            action: () {
              Navigator.pop(context);
              if (doublePop) {
                Navigator.pop(context);
              }
            },
            title: appLocalizationsOf(context).okEmphasized,
          ),
        ],
      );
}
