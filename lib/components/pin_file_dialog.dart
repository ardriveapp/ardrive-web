import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/turbo_payment_required_dialog.dart';
import 'package:ardrive/blocs/pin_file/pin_file_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/pages/user_interaction_wrapper.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
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
            crypto: ArDriveCrypto(),
          );
        },
        child: const PinFileDialog(),
      ),
    ),
  );
}

/// Whether the ID field says its text is not a valid ID.
///
/// Not while it is still being typed: every ID starts out as an incomplete
/// one, and the field said so from the first character. It says so once the
/// text is as long as the longest ID, holds a character no ID has, or is
/// [settled]: pasted, or left.
@visibleForTesting
bool showsInvalidIdError(String id, {required bool settled}) {
  const transactionIdLength = 43;
  final couldStillBecomeAnId = RegExp(r'^[\w\-+]*$').hasMatch(id);

  return settled || id.length >= transactionIdLength || !couldStillBecomeAnId;
}

/// How many characters an edit from [before] to [after] put in: what is left
/// of [after] once the text the two share at each end is taken away.
///
/// Typing puts in one, wherever the cursor is and whatever it replaces. A
/// paste puts in many, even when it replaces text as long as itself.
@visibleForTesting
int insertedLength(String before, String after) {
  var prefix = 0;
  while (prefix < before.length &&
      prefix < after.length &&
      before[prefix] == after[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < before.length - prefix &&
      suffix < after.length - prefix &&
      before[before.length - 1 - suffix] == after[after.length - 1 - suffix]) {
    suffix++;
  }
  return after.length - prefix - suffix;
}

class PinFileDialog extends StatefulWidget {
  const PinFileDialog({super.key});

  @override
  State<PinFileDialog> createState() => _PinFileDialogState();
}

class _PinFileDialogState extends State<PinFileDialog> {
  final _idFocusNode = FocusNode();

  /// Whether the reader is done with the ID: they pasted it, or left the
  /// field. From then on an invalid ID is said to be one, until the field is
  /// emptied and a new one is started.
  bool _idSettled = false;
  String _lastId = '';

  /// The field is disabled while the ID is looked up, which takes its focus.
  /// That is not the reader leaving it.
  bool _lookupRunning = false;

  @override
  void initState() {
    super.initState();
    _idFocusNode.addListener(() {
      if (!_idFocusNode.hasFocus && _lastId.isNotEmpty && !_lookupRunning) {
        setState(() => _idSettled = true);
      }
    });
  }

  @override
  void dispose() {
    _idFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinFileBloc = context.read<PinFileBloc>();

    return BlocConsumer<PinFileBloc, PinFileState>(
      listener: (context, state) {
        if (state is PinFileAbort || state is PinFileSuccess) {
          Navigator.of(context).pop();
        } else if (state is PinFileError) {
          if (state.isPaymentError) {
            Navigator.of(context).pop(); // close the pin dialog
            showTurboPaymentRequiredDialog(context);
          } else {
            showArDriveDialog(
              context,
              content: _errorDialog(
                context,
                errorText: appLocalizationsOf(context).pinFailedToUpload,
                doublePop: true,
              ),
            );
          }
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

        _lookupRunning = state is PinFileNetworkCheckRunning;
        final idValidationError = _getIdValidationError(context, state);
        final nameValidationError = _getNameValidationError(context, state);

        return ArDriveStandardModalNew(
          title: appLocalizationsOf(context).newFilePin,
          content: SizedBox(
            width: kMediumDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ArDriveTextFieldNew(
                  isEnabled: state is! PinFileNetworkCheckRunning,
                  label: appLocalizationsOf(context).enterTxIdOrFileId,
                  isFieldRequired: true,
                  errorMessage: idValidationError,
                  showErrorMessage: idValidationError != null,
                  focusNode: _idFocusNode,
                  onChanged: (value) {
                    if (value.isEmpty) {
                      // A new ID is being started.
                      _idSettled = false;
                    } else if (insertedLength(_lastId, value) > 1) {
                      // More than one character at once is a paste: the
                      // reader has given the whole ID.
                      _idSettled = true;
                    }
                    _lastId = value;
                    pinFileBloc.add(
                      FieldsChanged(id: value, name: state.name),
                    );
                  },
                ),
                // The field is disabled while the ID is looked up, which
                // otherwise reads as the dialog having frozen. Beside the
                // field, not in it: a label put inside the disabled field did
                // not reach the semantics tree, so a screen reader missed it.
                if (state is PinFileNetworkCheckRunning)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          appLocalizationsOf(context).lookingUpThisId,
                          style: ArDriveTypographyNew.of(context)
                              .paragraphNormal(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colorTokens
                                .textMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                ArDriveTextFieldNew(
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
              title: appLocalizationsOf(context).createPin,
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
    if (state.idValidation == IdValidationResult.invalid) {
      return showsInvalidIdError(state.id, settled: _idSettled)
          ? appLocalizationsOf(context).theIdProvidedIsNotValid
          : null;
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
    if (state.nameValidation == NameValidationResult.invalid) {
      return appLocalizationsOf(context).validationInvalid;
    } else if (state.nameValidation == NameValidationResult.required) {
      return appLocalizationsOf(context).validationRequired;
    } else if (state.nameValidation == NameValidationResult.conflicting) {
      return appLocalizationsOf(context).conflictingNameFound;
    }
    return null;
  }

  ArDriveStandardModalNew _errorDialog(
    BuildContext context, {
    required String errorText,
    bool doublePop = false,
  }) =>
      ArDriveStandardModalNew(
        width: kMediumDialogWidth,
        title: appLocalizationsOf(context).failedToCreatePin,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(errorText),
            ),
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
