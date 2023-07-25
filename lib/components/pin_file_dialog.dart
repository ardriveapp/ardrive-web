import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showPinFileDialog({
  required BuildContext context,
}) {
  final arweave = context.read<ArweaveService>();
  return showModalDialog(
    context,
    () => showAnimatedDialog(
      context,
      content: BlocProvider(
        create: (context) {
          final FileIdResolver fileIdResolver = NetworkFileIdResolver(
            arweave: arweave,
          );
          return PinFileBloc(fileIdResolver: fileIdResolver);
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
        if (state is PinFileAbort) {
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
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
                  // controller: pinFileBloc.idTextController,
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
                if (state is PinFileNetworkValidationError)
                  SizedBox(
                    width: kMediumDialogWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          !state.doesDataTransactionExist
                              ? 'Data transaction does not exist'
                              : !state.isArFsEntityPublic
                                  ? 'File is not public'
                                  : 'File is not valid',
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
              isEnable: state is PinFileFieldsValid,
            ),
          ],
        );
      },
    );
  }
}
