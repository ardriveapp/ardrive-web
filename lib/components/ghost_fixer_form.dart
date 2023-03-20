import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/ghost_fixer/ghost_fixer_cubit.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:responsive_builder/responsive_builder.dart';

import 'components.dart';

Future<void> promptToReCreateFolder(BuildContext context,
    {required FolderEntry ghostFolder}) {
  if (ghostFolder.parentFolderId != null) {
    return showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => GhostFixerCubit(
            ghostFolder: ghostFolder,
            profileCubit: context.read<ProfileCubit>(),
            arweave: context.read<ArweaveService>(),
            turboService: context.read<TurboService>(),
            driveDao: context.read<DriveDao>(),
            syncCubit: context.read<SyncCubit>()),
        child: const GhostFixerForm(),
      ),
    );
  } else {
    //TODO: Fix missing root folder;
    throw UnimplementedError();
  }
}

class GhostFixerForm extends StatelessWidget {
  const GhostFixerForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<GhostFixerCubit, GhostFixerState>(
          listener: (context, state) {
        if (state is GhostFixerRepairInProgress) {
          showProgressDialog(
              context, appLocalizationsOf(context).recreatingFolderEmphasized);
        } else if (state is GhostFixerSuccess) {
          Navigator.pop(context);
          Navigator.pop(context);
        } else if (state is GhostFixerWalletMismatch) {
          Navigator.pop(context);
        }
      }, builder: (context, state) {
        Widget _buildButtonBar() => ButtonBar(
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(appLocalizationsOf(context).cancelEmphasized)),
                ElevatedButton(
                  onPressed: () => context.read<GhostFixerCubit>().submit(),
                  child: Text(appLocalizationsOf(context).fixEmphasized),
                ),
              ],
            );
        Widget _buildCreateFolderButton() {
          if (state is GhostFixerFolderLoadSuccess) {
            return TextButton.icon(
              icon: const Icon(Icons.create_new_folder),
              label: Text(appLocalizationsOf(context).createFolderEmphasized),
              onPressed: () => promptToCreateFolderWithoutCongestionWarning(
                context,
                driveId: state.viewingFolder.folder.driveId,
                parentFolderId: state.viewingFolder.folder.id,
              ),
            );
          } else {
            return Container();
          }
        }

        return AppDialog(
          title: appLocalizationsOf(context).recreateFolderEmphasized,
          content: SizedBox(
            width: kLargeDialogWidth,
            height: 400,
            child: state is GhostFixerFolderLoadSuccess
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReactiveForm(
                        formGroup: context.watch<GhostFixerCubit>().form,
                        child: ReactiveTextField(
                          formControlName: 'name',
                          autofocus: true,
                          decoration: InputDecoration(
                              labelText:
                                  appLocalizationsOf(context).folderName),
                          showErrors: (control) =>
                              control.dirty && control.invalid,
                          validationMessages:
                              kValidationMessages(appLocalizationsOf(context)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(appLocalizationsOf(context).targetFolderEmphasized),
                      if (!state.viewingRootFolder)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextButton(
                              style: TextButton.styleFrom(
                                  textStyle:
                                      Theme.of(context).textTheme.subtitle2,
                                  padding: const EdgeInsets.all(16)),
                              onPressed: () => context
                                  .read<GhostFixerCubit>()
                                  .loadParentFolder(),
                              child: ListTile(
                                dense: true,
                                leading: const Icon(Icons.arrow_back),
                                title: Text(appLocalizationsOf(context).back),
                              )),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Scrollbar(
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                ...state.viewingFolder.subfolders.map(
                                  (f) => ListTile(
                                    key: ValueKey(f.id),
                                    dense: true,
                                    leading: const Icon(Icons.folder),
                                    title: Text(f.name),
                                    onTap: () => context
                                        .read<GhostFixerCubit>()
                                        .loadFolder(f.id),
                                    trailing: const Icon(
                                      Icons.keyboard_arrow_right,
                                    ),
                                    // Do not allow users to navigate into the folder they are currently trying to move.
                                    enabled: f.id != state.movingEntryId,
                                  ),
                                ),
                                ...state.viewingFolder.files.map(
                                  (f) => ListTile(
                                    key: ValueKey(f.id),
                                    leading: const Icon(
                                      Icons.insert_drive_file,
                                    ),
                                    title: Text(f.name),
                                    enabled: false,
                                    dense: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(),
                      Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: ScreenTypeLayout(
                            desktop: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildCreateFolderButton(),
                                _buildButtonBar(),
                              ],
                            ),
                            mobile: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                _buildCreateFolderButton(),
                                _buildButtonBar(),
                              ],
                            ),
                          )),
                    ],
                  )
                : const SizedBox(),
          ),
        );
      });
}
