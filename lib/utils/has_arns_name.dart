import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';

/// Checks if an ArDriveDataTableItem has ArNS names assigned.
bool hasArnsNames(ArDriveDataTableItem item) {
  return item is FileDataTableItem &&
      (item).assignedNames != null &&
      (item).assignedNames!.isNotEmpty;
}
