import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';

FileDataTableItem fileItem(
  String id, {
  String? name,
  String contentType = 'image/jpeg',
  DateTime? created,
  DateTime? updated,
  int size = 1000,
  List<Variant>? variants,
  bool isHidden = false,
  int index = 0,
}) {
  final date = created ?? DateTime(2026, 10, 15);
  return FileDataTableItem(
    driveId: 'drive',
    lastUpdated: updated ?? date,
    name: name ?? '$id.jpg',
    size: size,
    dateCreated: date,
    contentType: contentType,
    index: index,
    isOwner: true,
    isHidden: isHidden,
    fileId: id,
    parentFolderId: 'root',
    dataTxId: 'tx-$id',
    lastModifiedDate: date,
    metadataTx: null,
    dataTx: null,
    pinnedDataOwnerAddress: null,
    thumbnail: variants == null ? null : Thumbnail(variants: variants),
  );
}

FolderDataTableItem folderItem(String id, {String? name, int index = 0}) =>
    FolderDataTableItem(
      driveId: 'drive',
      folderId: id,
      name: name ?? id,
      lastUpdated: DateTime(2026, 1, 1),
      dateCreated: DateTime(2026, 1, 1),
      contentType: 'folder',
      index: index,
      isOwner: true,
    );

Variant variant(String txId, int w, int h, {int size = 20000}) =>
    Variant(name: 'v', txId: txId, size: size, width: w, height: h);
