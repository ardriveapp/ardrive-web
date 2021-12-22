part of '../drive_detail_page.dart';

Widget _buildDataList(BuildContext context, DriveDetailLoadSuccess state) =>
    ListView(
      children: [
        ...state.currentFolder.subfolders.map(
          (folder) => _buildFolderListTile(
            context: context,
            folder: folder,
            selected: folder.id == state.selectedItemId,
            onPressed: () {
              final bloc = context.read<DriveDetailCubit>();
              if (folder.id == state.selectedItemId) {
                bloc.openFolder(path: folder.path);
              } else {
                bloc.selectItem(
                  folder.id,
                  isFolder: true,
                );
              }
            },
          ),
        ),
        ...state.currentFolder.files.map(
          (file) => _buildFileListTile(
            context: context,
            file: file,
            selected: file.id == state.selectedItemId,
            onPressed: () async {
              final bloc = context.read<DriveDetailCubit>();
              if (file.id == state.selectedItemId) {
                bloc.toggleSelectedItemDetails();
              } else {
                await bloc.selectItem(file.id);
              }
            },
          ),
        )
      ].intersperse(Divider()).toList(),
    );

Widget _buildFolderListTile({
  required BuildContext context,
  required FolderEntry folder,
  required Function onPressed,
  bool selected = false,
}) =>
    ListTile(
      onTap: () => onPressed(),
      selected: selected,
      leading: Padding(
        padding: const EdgeInsetsDirectional.only(end: 8.0),
        child: const Icon(Icons.folder),
      ),
      title: Text(folder.name),
      trailing: folder.isGhost
          ? TextButton(
              style: TextButton.styleFrom(
                backgroundColor: kSecondarySwatch[300],
              ),
              onPressed: () =>
                  promptToReCreateFolder(context, ghostFolder: folder),
              child: Text('Fix'),
            )
          : null,
    );

Widget _buildFileListTile({
  required BuildContext context,
  required FileWithLatestRevisionTransactions file,
  required Function onPressed,
  bool selected = false,
}) =>
    ListTile(
      onTap: () => onPressed(),
      selected: selected,
      leading: Padding(
        padding: const EdgeInsetsDirectional.only(end: 8.0),
        child: _buildFileIcon(
          fileStatusFromTransactions(file.metadataTx, file.dataTx),
          file.dataContentType,
        ),
      ),
      title: Text(file.name),
      subtitle: Text(
        'Last Modified ' +
            (file.lastUpdated.difference(DateTime.now()).inDays > 3
                ? format(file.lastUpdated)
                : yMMdDateFormatter.format(file.lastUpdated)),
      ),
    );
