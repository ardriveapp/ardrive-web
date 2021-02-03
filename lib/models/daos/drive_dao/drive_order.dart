part of 'drive_dao.dart';

enum DriveOrder {
  name,
  size,
  lastUpdated,
}

OrderBy enumToFolderOrderByClause(FolderEntries table, DriveOrder orderBy,
    [OrderingMode orderingMode = OrderingMode.asc]) {
  switch (orderBy) {
    // Folders have no size or proper last updated time to be sorted by
    // so we just sort them ascendingly by name.
    case DriveOrder.lastUpdated:
    case DriveOrder.size:
      return OrderBy(
          [OrderingTerm(expression: table.name, mode: OrderingMode.asc)]);
    case DriveOrder.name:
    default:
      return OrderBy(
          [OrderingTerm(expression: table.name, mode: orderingMode)]);
  }
}

OrderBy enumToFileOrderByClause(FileEntries table, DriveOrder orderBy,
    [OrderingMode orderingMode = OrderingMode.asc]) {
  switch (orderBy) {
    case DriveOrder.lastUpdated:
      return OrderBy(
          [OrderingTerm(expression: table.lastUpdated, mode: orderingMode)]);
    case DriveOrder.size:
      return OrderBy(
          [OrderingTerm(expression: table.size, mode: orderingMode)]);
    case DriveOrder.name:
    default:
      return OrderBy(
          [OrderingTerm(expression: table.name, mode: orderingMode)]);
  }
}
