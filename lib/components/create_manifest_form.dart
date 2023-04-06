import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/blocs/feedback_survey/feedback_survey_cubit.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/usd_upload_cost_to_string.dart';
import 'package:ardrive/utils/validate_folder_name.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components.dart';

Future<void> promptToCreateManifest(
  BuildContext context, {
  required Drive drive,
}) {
  return showAnimatedDialog(
    context,
    content: BlocProvider(
      create: (context) => CreateManifestCubit(
        drive: drive,
        profileCubit: context.read<ProfileCubit>(),
        arweave: context.read<ArweaveService>(),
        turboService: context.read<TurboService>(),
        driveDao: context.read<DriveDao>(),
        pst: context.read<PstService>(),
      ),
      child: CreateManifestForm(),
    ),
  );
}

class CreateManifestForm extends StatefulWidget {
  CreateManifestForm({Key? key}) : super(key: key);

  @override
  State<CreateManifestForm> createState() => _CreateManifestFormState();
}

class _CreateManifestFormState extends State<CreateManifestForm> {
  final _manifestNameController = TextEditingController();

  bool _isFormValid = false;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<CreateManifestCubit, CreateManifestState>(
          listener: (context, state) {
        if (state is CreateManifestUploadInProgress) {
          showProgressDialog(
            context,
            title: appLocalizationsOf(context).uploadingManifestEmphasized,
          );
        } else if (state is CreateManifestPreparingManifest) {
          showProgressDialog(
            context,
            title: appLocalizationsOf(context).preparingManifestEmphasized,
          );
        } else if (state is CreateManifestSuccess ||
            state is CreateManifestPrivacyMismatch) {
          Navigator.pop(context);
          Navigator.pop(context);
          context.read<FeedbackSurveyCubit>().openRemindMe();
        }
      }, builder: (context, state) {
        final readCubitContext = context.read<CreateManifestCubit>();

        ArDriveTextField manifestNameForm() => ArDriveTextField(
              controller: _manifestNameController,
              validator: (value) {
                final validation = validateEntityName(value, context);

                _isFormValid = validation == null;

                setState(() {});

                return validation;
              },
              autofocus: true,
            );

        ArDriveStandardModal errorDialog({required String errorText}) =>
            ArDriveStandardModal(
              width: kMediumDialogWidth,
              title:
                  appLocalizationsOf(context).failedToCreateManifestEmphasized,
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
                  title: appLocalizationsOf(context).continueEmphasized,
                ),
              ],
            );

        if (state is CreateManifestWalletMismatch) {
          Navigator.pop(context);
          return errorDialog(
            errorText:
                appLocalizationsOf(context).walletChangedDuringManifestCreation,
          );
        }

        if (state is CreateManifestFailure) {
          Navigator.pop(context);
          return errorDialog(
            errorText: appLocalizationsOf(context)
                .manifestTransactionUnexpectedlyFailed,
          );
        }

        if (state is CreateManifestInsufficientBalance) {
          Navigator.pop(context);
          return errorDialog(
            errorText: appLocalizationsOf(context)
                .insufficientBalanceForManifest(
                    state.walletBalance, state.totalCost),
          );
        }

        if (state is CreateManifestNameConflict) {
          return ArDriveStandardModal(
            width: kMediumDialogWidth,
            title: appLocalizationsOf(context).conflictingNameFound,
            content: SizedBox(
              height: 200,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    appLocalizationsOf(context)
                        .conflictingManifestFoundChooseNewName,
                  ),
                  manifestNameForm()
                ],
              ),
            ),
            actions: [
              ModalAction(
                action: () => Navigator.of(context).pop(false),
                title: appLocalizationsOf(context).cancelEmphasized,
              ),
              ModalAction(
                action: () => readCubitContext
                    .reCheckConflicts(_manifestNameController.text),
                title: appLocalizationsOf(context).continueEmphasized,
              ),
            ],
          );
        }

        if (state is CreateManifestRevisionConfirm) {
          return ArDriveStandardModal(
            width: kMediumDialogWidth,
            title: appLocalizationsOf(context).conflictingManifestFound,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text(
                  appLocalizationsOf(context)
                      .conflictingManifestFoundChooseNewName,
                ),
                const SizedBox(height: 16),
              ],
            ),
            actions: [
              ModalAction(
                action: () => Navigator.of(context).pop(false),
                title: appLocalizationsOf(context).cancelEmphasized,
              ),
              ModalAction(
                isEnable: _isFormValid,
                action: () => readCubitContext
                    .confirmRevision(_manifestNameController.text),
                title: appLocalizationsOf(context).continueEmphasized,
              ),
            ],
          );
        }

        if (state is CreateManifestInitial) {
          return ArDriveStandardModal(
              width: kLargeDialogWidth,
              title: appLocalizationsOf(context).addnewManifestEmphasized,
              actions: [
                ModalAction(
                  action: () => Navigator.pop(context),
                  title: appLocalizationsOf(context).cancelEmphasized,
                ),
                ModalAction(
                  action: () => readCubitContext.chooseTargetFolder(),
                  title: appLocalizationsOf(context).nextEmphasized,
                ),
              ],
              content: SizedBox(
                height: 250,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(
                                text: appLocalizationsOf(context)
                                    .aManifestIsASpecialKindOfFile, // trimmed spaces
                                style: Theme.of(context).textTheme.bodyText1),
                            TextSpan(
                              text: ' ${appLocalizationsOf(context).learnMore}',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyText1
                                      ?.color,
                                  fontSize: Theme.of(context)
                                      .textTheme
                                      .bodyText1
                                      ?.fontSize,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => openUrl(
                                      url: Resources.manifestLearnMoreLink,
                                    ),
                            ),
                          ]),
                        ),
                        manifestNameForm()
                      ],
                    )),
              ));
        }
        if (state is CreateManifestTurboUploadConfirmation) {
          Navigator.pop(context);
          return ArDriveStandardModal(
            width: kMediumDialogWidth,
            title: appLocalizationsOf(context).createManifestEmphasized,
            content: SizedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 256),
                    child: Scrollbar(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              state.manifestName,
                              style: ArDriveTypography.body.buttonNormalRegular(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgOnAccent,
                              ),
                            ),
                            subtitle: Text(
                              filesize(state.manifestSize),
                              style: ArDriveTypography.body.buttonNormalRegular(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeFgOnDisabled),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    appLocalizationsOf(context).freeTurboTransaction,
                    style: Theme.of(context).textTheme.bodyText1,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    appLocalizationsOf(context)
                        .filesWillBePermanentlyPublicWarning,
                    style: Theme.of(context).textTheme.bodyText2,
                  ),
                ],
              ),
            ),
            actions: [
              ModalAction(
                action: () => Navigator.of(context).pop(false),
                title: appLocalizationsOf(context).cancelEmphasized,
              ),
              ModalAction(
                action: () => readCubitContext.uploadManifest(),
                title: appLocalizationsOf(context).confirmEmphasized,
              ),
            ],
          );
        }
        if (state is CreateManifestUploadConfirmation) {
          Navigator.pop(context);
          return ArDriveStandardModal(
            width: kMediumDialogWidth,
            title: appLocalizationsOf(context).createManifestEmphasized,
            content: SizedBox(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 256),
                    child: Scrollbar(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              state.manifestName,
                              style:
                                  ArDriveTypography.body.buttonNormalRegular(),
                            ),
                            subtitle: Text(
                              filesize(state.manifestSize),
                              style: ArDriveTypography.body.buttonNormalRegular(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeFgOnDisabled),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: appLocalizationsOf(context)
                              .cost(state.arUploadCost),
                        ),
                        TextSpan(
                          text: usdUploadCostToString(state.usdUploadCost),
                        ),
                      ],
                      style: Theme.of(context).textTheme.bodyText1,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    appLocalizationsOf(context)
                        .filesWillBePermanentlyPublicWarning,
                    style: Theme.of(context).textTheme.bodyText2,
                  ),
                ],
              ),
            ),
            actions: [
              ModalAction(
                action: () => Navigator.of(context).pop(false),
                title: appLocalizationsOf(context).cancelEmphasized,
              ),
              ModalAction(
                action: () => readCubitContext.uploadManifest(),
                title: appLocalizationsOf(context).confirmEmphasized,
              ),
            ],
          );
        }

        if (state is CreateManifestFolderLoadSuccess) {
          return _selectFolder(state, context);
          return ArDriveStandardModal(
            width: kLargeDialogWidth,
            title: appLocalizationsOf(context).createManifestEmphasized,
            actions: [
              ModalAction(
                action: () => readCubitContext.backToName(),
                title: appLocalizationsOf(context).backEmphasized,
              ),
              ModalAction(
                action: () => readCubitContext
                    .checkForConflicts(_manifestNameController.text),
                title: appLocalizationsOf(context).createHereEmphasized,
              ),
            ],
            content: _selectFolder(state, context),
            //  SizedBox(
            //     height: 300,
            //     child: Column(
            //       mainAxisSize: MainAxisSize.min,
            //       mainAxisAlignment: MainAxisAlignment.center,
            //       crossAxisAlignment: CrossAxisAlignment.center,
            //       children: [
            //         Text(appLocalizationsOf(context).targetFolderEmphasized),
            //         if (!state.viewingRootFolder)
            //           Padding(
            //             padding: const EdgeInsets.only(bottom: 8),
            //             child: TextButton(
            //               style: TextButton.styleFrom(
            //                 textStyle: Theme.of(context).textTheme.subtitle2,
            //                 padding: const EdgeInsets.all(16),
            //               ),
            //               onPressed: () => readCubitContext.loadParentFolder(),
            //               child: ListTile(
            //                 dense: true,
            //                 leading: const Icon(Icons.arrow_back),
            //                 title: Text(appLocalizationsOf(context).back),
            //               ),
            //             ),
            //           ),
            //         Expanded(
            //           child: Padding(
            //             padding: const EdgeInsets.symmetric(horizontal: 16),
            //             child: _selectFolder(state, context),
            // Scrollbar(
            //   child: ListView(
            //     shrinkWrap: true,
            //     children: [
            //       ...state.viewingFolder.subfolders.map(
            //         (f) => ListTile(
            //           key: ValueKey(f.id),
            //           dense: true,
            //           leading: const Icon(Icons.folder),
            //           title: Text(f.name),
            //           onTap: () =>
            //               readCubitContext.loadFolder(f.id),
            //           trailing:
            //               const Icon(Icons.keyboard_arrow_right),
            //           enabled: !_isFolderEmpty(
            //             f.id,
            //             readCubitContext.rootFolderNode,
            //           ),
            //         ),
            //       ),
            //       ...state.viewingFolder.files
            //           .where((f) =>
            //               // New manifests will not include existing manifests
            //               // So we will not display them to the user by filtering them out
            //               f.dataContentType != ContentType.manifest)
            //           .map(
            //             (f) => ListTile(
            //               key: ValueKey(f.id),
            //               leading:
            //                   const Icon(Icons.insert_drive_file),
            //               title: Text(f.name),
            //               enabled: false,
            //               dense: true,
            //             ),
            //           ),
            //     ],
            //   ),
            // ),
            // ),
            // ),
            // ],
            // )),
          );
        }
        return const SizedBox();
      });

  bool _isFolderEmpty(FolderID folderId, FolderNode rootFolderNode) {
    final folderNode = rootFolderNode.searchForFolder(folderId);

    if (folderNode == null) {
      return true;
    }

    return folderNode.isEmpty();
  }

  Widget _selectFolder(
      CreateManifestFolderLoadSuccess state, BuildContext context) {
    final cubit = context.read<CreateManifestCubit>();

    final items = <Widget>[
      ...state.viewingFolder.subfolders.map(
        (f) {
          final enabled = !_isFolderEmpty(
            f.id,
            context.read<CreateManifestCubit>().rootFolderNode,
          );

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16),
            child: GestureDetector(
              onTap: enabled
                  ? () {
                      cubit.loadFolder(f.id);
                    }
                  : null,
              child: Row(
                children: [
                  ArDriveIcons.folderOutlined(
                    size: 16,
                    color: enabled ? null : _colorDisabled(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.name,
                      style: ArDriveTypography.body.inputNormalRegular(
                        color: enabled ? null : _colorDisabled(context),
                      ),
                    ),
                  ),
                  ArDriveIcons.chevronRight(
                    size: 18,
                    color: enabled ? null : _colorDisabled(context),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      ...state.viewingFolder.files
          .map(
            (f) => Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 16.0,
                horizontal: 16,
              ),
              child: Row(
                children: [
                  ArDriveIcons.fileOutlined(
                    size: 16,
                    color: _colorDisabled(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.name,
                      style: ArDriveTypography.body.inputNormalRegular(
                        color: _colorDisabled(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ];

    return ArDriveCard(
      height: 441,
      contentPadding: EdgeInsets.zero,
      width: kMediumDialogWidth,
      content: SizedBox(
        height: 325,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.only(left: 16, right: 16),
              width: double.infinity,
              height: 77,
              alignment: Alignment.centerLeft,
              color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
              child: Row(
                children: [
                  AnimatedContainer(
                    width: !state.viewingRootFolder ? 20 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: GestureDetector(
                      onTap: () {
                        cubit.loadParentFolder();
                      },
                      child: ArDriveIcons.arrowBack(
                        size: 20,
                      ),
                    ),
                  ),
                  AnimatedPadding(
                    duration: const Duration(milliseconds: 200),
                    padding: !state.viewingRootFolder
                        ? const EdgeInsets.only(left: 8)
                        : const EdgeInsets.only(left: 0),
                    child: Text(
                      appLocalizationsOf(context).targetFolderEmphasized,
                      style: ArDriveTypography.headline.headline5Bold(),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: ArDriveIcons.closeIcon(
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return items[index];
                },
              ),
            ),
            const Divider(),
            Container(
              decoration: BoxDecoration(
                color: ArDriveTheme.of(context).themeData.colors.themeBgSurface,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ArDriveButton(
                    maxHeight: 36,
                    backgroundColor: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                    fontStyle: ArDriveTypography.body.buttonNormalRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeAccentSubtle,
                    ),
                    text: appLocalizationsOf(context).createHereEmphasized,
                    onPressed: () {
                      cubit.checkForConflicts(_manifestNameController.text);
                    },
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Color _colorDisabled(BuildContext context) =>
      ArDriveTheme.of(context).themeData.colors.themeInputPlaceholder;
}
