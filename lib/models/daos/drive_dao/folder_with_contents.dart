part of 'drive_dao.dart';

class FolderWithContents extends Equatable {
  final List<FolderEntry> _subfolders;
  final List<FileWithLatestRevisionTransactions> _files;
  final FolderEntry _folder;

  List<FolderEntry> get subfolders {
    return _subfolders;
  }

  List<FileWithLatestRevisionTransactions> get files {
    return _files;
  }

  FolderEntry get folder => _folder;

  const FolderWithContents({
    required List<FolderEntry> subfolders,
    required List<FileWithLatestRevisionTransactions> files,
    required FolderEntry folder,
  })  : _subfolders = subfolders,
        _files = files,
        _folder = folder;

  @override
  List<Object> get props => [_folder, _subfolders, _files];
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
