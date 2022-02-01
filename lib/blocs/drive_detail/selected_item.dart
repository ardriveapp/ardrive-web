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

  bool isFile() => selectedFile != null;
  bool isFolder() => selectedFolder != null;
  bool isGhost() => selectedFolder?.isGhost ?? false;

  String getID() => selectedFile?.id ?? selectedFolder!.id;
}
