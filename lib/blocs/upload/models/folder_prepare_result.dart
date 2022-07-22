import 'package:ardrive/blocs/upload/models/io_file.dart';
import 'package:ardrive/blocs/upload/models/web_file.dart';
import 'package:ardrive/blocs/upload/models/web_folder.dart';

class FolderPrepareResult {
  List<IOFile> files;
  Map<String, WebFolder> foldersByPath;
  FolderPrepareResult({
    required this.files,
    required this.foldersByPath,
  });
}
