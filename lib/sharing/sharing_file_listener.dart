import 'package:ardrive/components/components.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/pages/drive_detail/components/drive_explorer_item_tile.dart';
import 'package:ardrive/sharing/blocs/sharing_file_bloc.dart';
import 'package:ardrive/sharing/folder_selector/folder_selector.dart';
import 'package:ardrive/sharing/folder_selector/folder_selector_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SharingFileListener extends StatefulWidget {
  const SharingFileListener({super.key, required this.child});

  final Widget child;

  @override
  State<SharingFileListener> createState() => _SharingFileListenerState();
}

class _SharingFileListenerState extends State<SharingFileListener> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SharingFileBloc, SharingFileState>(
      listener: (context, state) {
        final sharingFileBloc = context.read<SharingFileBloc>();
        if (state is SharingFileReceivedState) {
          showArDriveDialog(
            context,
            content: ArDriveStandardModal(
              title: appLocalizationsOf(context).shareFile,
              actions: [
                ModalAction(
                  action: () {
                    Navigator.of(context).pop();
                    sharingFileBloc.add(SharingFileCleared());
                  },
                  title: appLocalizationsOf(context).cancel,
                ),
                ModalAction(
                  action: () {
                    Navigator.of(context).pop();
                    showArDriveDialog(
                      context,
                      content: BlocProvider(
                        create: (context) => FolderSelectorBloc(
                          context.read<DriveDao>(),
                        ),
                        child: FolderSelector(
                          onSelect: (folderId, driveId) {
                            promptToUpload(
                              context,
                              driveId: driveId,
                              parentFolderId: folderId,
                              isFolderUpload: false,
                              files: state.files,
                            );
                          },
                          dispose: () {
                            sharingFileBloc.add(SharingFileCleared());
                          },
                        ),
                      ),
                    );
                  },
                  // TODO: Localize
                  title: 'Select Drive',
                ),
              ],
              content: SizedBox(
                height: 400,
                child: ListView.builder(
                  itemCount: state.files.length,
                  shrinkWrap: true,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: getIconForContentType(
                        state.files[index].contentType,
                        size: 24,
                      ),
                      title: Text(
                        state.files[index].name,
                        style: ArDriveTypography.body.buttonLargeBold(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        }
      },
      child: widget.child,
    );
  }
}
