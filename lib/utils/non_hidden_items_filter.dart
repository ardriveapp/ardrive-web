import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';

bool dataTableNotHiddenFilter(ArDriveDataTableItem item) {
  return !item.isHidden;
}

bool folderEntryNotHiddenFilter(FolderEntry entry) {
  return !entry.isHidden;
}

bool fileEntryNotHiddenFilter(FileWithLatestRevisionTransactions entry) {
  return !entry.isHidden;
}
