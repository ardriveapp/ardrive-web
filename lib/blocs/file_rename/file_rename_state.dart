part of 'file_rename_cubit.dart';

abstract class FileRenameState extends Equatable {
  const FileRenameState();

  @override
  List<Object> get props => [];
}

class FileRenameInitial extends FileRenameState {}

class FileRenameInProgress extends FileRenameState {}

class FileRenameSuccess extends FileRenameState {}
