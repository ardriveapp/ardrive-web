part of '../drive_detail_page.dart';

Widget _buildDataList(BuildContext context, DriveDetailLoadSuccess state) =>
    ListView(
      children: [
        ...state.folderInView.subfolders.map(
          (folder) => _buildFolderListTile(
            context: context,
            folder: folder,
            selected: folder.id == state.maybeSelectedItem()?.id,
            onPressed: () {
              final bloc = context.read<DriveDetailCubit>();
              if (folder.id == state.maybeSelectedItem()?.id) {
                bloc.openFolder(path: folder.path);
              } else {
                bloc.selectItem(SelectedFolder(folder: folder));
              }
            },
          ),
        ),
        ...state.folderInView.files.map(
          (file) => _buildFileListTile(
            context: context,
            file: file,
            selected: file.id == state.maybeSelectedItem()?.id,
            onPressed: () async {
              final bloc = context.read<DriveDetailCubit>();
              if (file.id == state.maybeSelectedItem()?.id) {
                bloc.toggleSelectedItemDetails();
              } else {
                await bloc.selectItem(SelectedFile(file: file));
              }
            },
          ),
        ),
        // TODO: maybe there's a better way to place this blank space
        // FIXME: remove the extra divider at the end
        // TODO: make it conditional?
        const SizedBox(
          height: 128,
        ),
      ].intersperse(const Divider()).toList(),
    );

Widget _buildFolderListTile({
  required BuildContext context,
  required FolderEntry folder,
  required Function onPressed,
  bool selected = false,
}) =>
    ArDriveCard(
        content: ListTile(
      onTap: () => onPressed(),
      selected: selected,
      leading: const Padding(
        padding: EdgeInsetsDirectional.only(end: 8.0),
        child: Icon(Icons.folder),
      ),
      title: Text(folder.name),
      trailing: folder.isGhost
          ? ElevatedButton(
              style: ElevatedButton.styleFrom(
                primary: LightColors.kOnLightSurfaceMediumEmphasis,
                textStyle: const TextStyle(
                    color: LightColors.kOnDarkSurfaceHighEmphasis),
              ),
              onPressed: () => showCongestionDependentModalDialog(
                context,
                () => promptToReCreateFolder(context, ghostFolder: folder),
              ),
              child: Text(appLocalizationsOf(context).fix),
            )
          : null,
    ));

Widget _buildFileListTile({
  required BuildContext context,
  required FileWithLatestRevisionTransactions file,
  required Function onPressed,
  bool selected = false,
}) =>
    ArDriveCard(
      content: ListTile(
        onTap: () => onPressed(),
        selected: selected,
        leading: Padding(
          padding: const EdgeInsetsDirectional.only(end: 8.0),
          child: _buildFileIcon(
            fileStatusFromTransactions(file.metadataTx, file.dataTx),
            file.dataContentType,
            appLocalizationsOf(context),
          ),
        ),
        title: Text(file.name),
        subtitle: Text(
          appLocalizationsOf(context).lastModifiedDate(
              (file.lastUpdated.difference(DateTime.now()).inDays > 3
                  ? format(file.lastUpdated)
                  : yMMdDateFormatter.format(file.lastUpdated))),
        ),
      ),
    );
