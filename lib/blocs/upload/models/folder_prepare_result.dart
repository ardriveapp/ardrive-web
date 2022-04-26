import 'package:ardrive/blocs/upload/models/web_file.dart';
import 'package:ardrive/blocs/upload/models/web_folder.dart';

class FolderPrepareResult {
  List<WebFile> files;
  Map<String, WebFolder> foldersByPath;
  FolderPrepareResult({
    required this.files,
    required this.foldersByPath,
  });
}
