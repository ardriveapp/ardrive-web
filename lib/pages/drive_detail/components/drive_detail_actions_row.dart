import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/link.dart';

class DriveDetailActionRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bloc = context.watch<DriveDetailCubit>();

    return BlocBuilder<DriveDetailCubit, DriveDetailState>(
      builder: (context, state) {
        if (state is DriveDetailLoadSuccess) {
          final fsActions = <Widget>[
            if (state.selectedItemId != null) ...{
              if (!state.selectedItemIsFolder) ...{
                IconButton(
                  icon: const Icon(Icons.file_download),
                  onPressed: () => promptToDownloadFile(
                    context,
                    driveId: state.currentDrive.id,
                    fileId: state.selectedItemId,
                  ),
                  tooltip: 'Download',
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Share',
                ),
                if (state.currentDrive.isPublic)
                  Link(
                    uri: state.selectedFilePreviewUrl,
                    target: LinkTarget.blank,
                    builder: (context, followLink) => IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: followLink,
                      tooltip: 'Preview',
                    ),
                  ),
              },
              if (state.hasWritePermissions) ...{
                IconButton(
                  icon: const Icon(Icons.drive_file_rename_outline),
                  onPressed: () {
                    if (state.selectedItemIsFolder) {
                      promptToRenameFolder(context,
                          driveId: state.currentDrive.id,
                          folderId: state.selectedItemId);
                    } else {
                      promptToRenameFile(context,
                          driveId: state.currentDrive.id,
                          fileId: state.selectedItemId);
                    }
                  },
                  tooltip: 'Rename',
                ),
                IconButton(
                  icon: const Icon(Icons.drive_file_move),
                  onPressed: () {
                    if (state.selectedItemIsFolder) {
                      promptToMoveFolder(context,
                          driveId: state.currentDrive.id,
                          folderId: state.selectedItemId);
                    } else {
                      promptToMoveFile(context,
                          driveId: state.currentDrive.id,
                          fileId: state.selectedItemId);
                    }
                  },
                  tooltip: 'Move',
                ),
              },
            },
          ];

          return Row(
            children: [
              ...fsActions,
              if (fsActions.isNotEmpty)
                const SizedBox(height: 32, child: VerticalDivider()),
              if (!state.hasWritePermissions)
                IconButton(
                  icon: const Icon(Icons.remove_red_eye),
                  onPressed: () => bloc.toggleSelectedItemDetails(),
                  tooltip: 'View Only',
                ),
              state.currentDrive.isPrivate
                  ? IconButton(
                      icon: const Icon(Icons.lock),
                      onPressed: () => bloc.toggleSelectedItemDetails(),
                      tooltip: 'Private',
                    )
                  : IconButton(
                      icon: const Icon(Icons.public),
                      onPressed: () => bloc.toggleSelectedItemDetails(),
                      tooltip: 'Public',
                    ),
              IconButton(
                icon: const Icon(Icons.info),
                onPressed: () => bloc.toggleSelectedItemDetails(),
                tooltip: 'View Info',
              ),
            ],
          );
        }

        return Container();
      },
    );
  }
}
