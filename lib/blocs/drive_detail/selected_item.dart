import 'package:ardrive/models/models.dart';

class SelectedItem {
  FolderEntry? selectedFolder;
  FileWithLatestRevisionTransactions? selectedFile;

  SelectedItem({
    this.selectedFolder,
    this.selectedFile,
  }) {
    assert(selectedFile != null || selectedFolder != null, true);
  }

  SelectedItemType getItemType() {
    if (selectedFile != null) {
      return SelectedItemType.File;
    } else if (selectedFolder != null && selectedFolder!.isGhost) {
      return SelectedItemType.Ghost;
    } else if (selectedFolder != null) {
      return SelectedItemType.Folder;
    } else {
      throw UnimplementedError();
    }
  }

  String getID() => selectedFile?.id ?? selectedFolder!.id;
}

enum SelectedItemType {
  File,
  Folder,
  Ghost,
  Manifest,
}
