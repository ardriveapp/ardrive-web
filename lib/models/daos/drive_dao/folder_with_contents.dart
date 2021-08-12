part of 'drive_dao.dart';

class FolderWithContents extends Equatable {
  final FolderEntry? folder;
  final List<FolderEntry>? subfolders;
  final List<FileWithLatestRevisionTransactions>? files;

  FolderWithContents({this.folder, this.subfolders, this.files});

  @override
  List<Object?> get props => [folder, subfolders, files];
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
