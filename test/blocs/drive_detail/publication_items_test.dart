import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/enums.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:flutter_test/flutter_test.dart';

final _date = DateTime.utc(2026, 10, 22);

FolderDataTableItem _folder({bool hidden = false, bool ghost = false}) =>
    FolderDataTableItem(
      driveId: 'd',
      folderId: 'f',
      name: 'folder',
      lastUpdated: _date,
      dateCreated: _date,
      contentType: 'folder',
      isHidden: hidden,
      index: 0,
      isOwner: false,
      isGhostFolder: ghost,
    );

FileDataTableItem _file({bool hidden = false, String? status}) =>
    FileDataTableItem(
      driveId: 'd',
      lastUpdated: _date,
      name: 'file',
      size: 1,
      dateCreated: _date,
      contentType: 'text/plain',
      isHidden: hidden,
      fileStatusFromTransactions: status,
      index: 0,
      isOwner: false,
      fileId: 'file',
      parentFolderId: 'f',
      dataTxId: 'tx',
      lastModifiedDate: _date,
      metadataTx: null,
      dataTx: null,
      pinnedDataOwnerAddress: null,
    );

/// docs/PUBLICATIONS.md, "Never shown".
void main() {
  bool shown(item) => DriveDetailCubit.isShownInPublication(item);

  test('shows a folder and a confirmed file', () {
    expect(shown(_folder()), isTrue);
    expect(shown(_file(status: TransactionStatus.confirmed)), isTrue);
    expect(shown(_file()), isTrue);
  });

  test('never shows hidden items', () {
    expect(shown(_folder(hidden: true)), isFalse);
    expect(shown(_file(hidden: true, status: TransactionStatus.confirmed)),
        isFalse);
  });

  test('never shows ghost folders', () {
    expect(shown(_folder(ghost: true)), isFalse);
  });

  test('never shows failed or pending uploads', () {
    expect(shown(_file(status: TransactionStatus.failed)), isFalse);
    expect(shown(_file(status: TransactionStatus.pending)), isFalse);
  });
}
