part of 'drive_dao.dart';

class FolderWithContents extends Equatable {
  final List<FolderEntry> subfolders;
  final List<FileWithLatestRevisionTransactions> files;
  final FolderEntry folder;

  FolderWithContents(
      {required this.folder, required this.subfolders, required this.files});

  @override
  List<Object> get props => [folder, subfolders, files];
}

String fileStatusFromTransactions(
    NetworkTransaction metadataTx, NetworkTransaction dataTx) {
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

class FolderWatcher {
  FolderWithContents? folderEntry;
  FolderWatcher({this.folderEntry});
}
