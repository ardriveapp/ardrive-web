import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
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
        if (state is PinFileAbort ||
            state is PinFileSuccess ||
            state is PinFileError) {
          // FIXME: give some feedback on error
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        String? customErrorMessage;

        if (state is PinFileFieldsValidationError) {
          if (!state.doesDataTransactionExist) {
            customErrorMessage = 'File data transaction does not exist';
          } else if (!state.isArFsEntityPublic) {
            customErrorMessage = 'File is not public';
          } else if (!state.isArFsEntityValid) {
            customErrorMessage = 'File is not valid';
          }
        }

        if (customErrorMessage == null) {
          if (state.nameValidation == NameValidationResult.conflicting) {
            customErrorMessage = 'That name already exists';
          }
        }

        return ArDriveStandardModal(
          title: 'Testing title',
          content: SizedBox(
            width: kMediumDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArDriveTextField(
                  isEnabled: state is! PinFileNetworkCheckRunning,
                  label: 'Tx ID or File ID',
                  hintText: 'Enter id',
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
                        return 'Id is invalid';
                      }
                    }
                    return null;
                  },
                ),
                ArDriveTextField(
                  isEnabled: true,
                  label: 'Pin name',
                  hintText: 'Enter name',
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
                        return 'Name is invalid';
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
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          customErrorMessage,
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
              title: 'Cancel',
            ),
            ModalAction(
              action: () => pinFileBloc.add(const PinFileSubmit()),
              title: 'Create',
              // FIXME: "isEnabled"
              isEnable: state is PinFileFieldsValid &&
                  state.nameValidation == NameValidationResult.valid,
            ),
          ],
        );
      },
    );
  }
}
