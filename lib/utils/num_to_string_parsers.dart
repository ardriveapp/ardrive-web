import 'package:flutter_gen/gen_l10n/app_localizations.dart';

String fileAndFolderCountsToString({
  required int folderCount,
  required int fileCount,
  required AppLocalizations localizations,
}) {
  if (folderCount == 1 && fileCount == 1) {
    // 1-1
    return localizations.folderAndFile(folderCount, fileCount);
  } else if (folderCount == 1 && fileCount > 1) {
    // 1-N
    return localizations.folderAndFiles(folderCount, fileCount);
  } else if (folderCount > 1 && fileCount == 1) {
    // N-1
    return localizations.foldersAndFile(folderCount, fileCount);
  } else if (folderCount > 1 && fileCount > 1) {
    // N-N
    return localizations.foldersAndFiles(folderCount, fileCount);
  } else if (folderCount == 0 && fileCount == 1) {
    // 0-1
    return localizations.zeroFoldersAndFile(folderCount, fileCount);
  } else if (folderCount == 1 && fileCount == 0) {
    // 1-0
    return localizations.folderAndZeroFiles(folderCount, fileCount);
  } else if (folderCount == 0 && fileCount == 0) {
    // 0-0
    return localizations.zeroFoldersAndZeroFiles(folderCount, fileCount);
  } else if (folderCount > 1 && fileCount == 0) {
    // N-0
    return localizations.foldersAndZeroFiles(folderCount, fileCount);
  } else {
    // 0-N
    return localizations.zeroFoldersAndFiles(folderCount, fileCount);
  }
}
