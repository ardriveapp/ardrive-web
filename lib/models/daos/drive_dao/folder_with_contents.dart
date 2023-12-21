part of 'drive_dao.dart';

class FolderWithContents extends Equatable {
  final List<FolderEntry> _subfolders;
  final List<FileWithLatestRevisionTransactions> _files;
  final FolderEntry _folder;
  // final bool showHiddenFiles;

  List<FolderEntry> get subfolders {
    // if (showHiddenFiles) {
    return _subfolders;
    // } else {
    //   return _subfolders
    //       .where((folder) => !_isHiddenFolderFilter(folder))
    //       .toList();
    // }
  }

  List<FileWithLatestRevisionTransactions> get files {
    // if (showHiddenFiles) {
    return _files;
    // } else {
    //   return _files.where((file) => !_isHiddenFileFilter(file)).toList();
    // }
  }

  FolderEntry get folder => _folder;

  const FolderWithContents({
    required List<FolderEntry> subfolders,
    required List<FileWithLatestRevisionTransactions> files,
    required FolderEntry folder,
    // required this.showHiddenFiles,
  })  : _subfolders = subfolders,
        _files = files,
        _folder = folder;

  @override
  List<Object> get props => [_folder, _subfolders, _files];

  // bool _isHiddenFolderFilter(FolderEntry folder) {
  //   return folder.isHidden;
  // }

  // bool _isHiddenFileFilter(FileWithLatestRevisionTransactions file) {
  //   return file.isHidden;
  // }
}

String fileStatusFromTransactions(
  NetworkTransaction metadataTx,
  NetworkTransaction dataTx,
) {
  if (metadataTx.status == TransactionStatus.failed ||
      dataTx.status == TransactionStatus.failed) {
    return TransactionStatus.failed;
  } else if (metadataTx.status == TransactionStatus.pending ||
      dataTx.status == TransactionStatus.pending) {
    return TransactionStatus.pending;
  } else {
    return TransactionStatus.confirmed;
  }
}
