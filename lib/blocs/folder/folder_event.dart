part of 'folder_bloc.dart';

@immutable
abstract class FolderEvent {}

class SubfolderAdded extends FolderEvent {
  final Folder subfolder;

  SubfolderAdded(this.subfolder);
}

class FileAdded extends FolderEvent {
  final File file;

  FileAdded(this.file);
}
