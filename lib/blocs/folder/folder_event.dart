import 'package:drive/repositories/repositories.dart';

abstract class FolderEvent {}

class SubfolderAdded extends FolderEvent {
  Folder subfolder;

  SubfolderAdded(this.subfolder);
}

class FileAdded extends FolderEvent {
  File file;

  FileAdded(this.file);
}
