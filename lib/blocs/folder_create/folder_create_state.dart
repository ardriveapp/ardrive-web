part of 'folder_create_cubit.dart';

@immutable
abstract class FolderCreateState extends Equatable {
  @override
  List<Object> get props => [];
}

class FolderCreateInitial extends FolderCreateState {}

class FolderCreateInProgress extends FolderCreateState {}

class FolderCreateSuccess extends FolderCreateState {}

class FolderCreateFailure extends FolderCreateState {}

class FolderCreateWalletMismatch extends FolderCreateState {}

class FolderCreateNameAlreadyExists extends FolderCreateState {
  final String folderName;

  FolderCreateNameAlreadyExists({required this.folderName});
}
