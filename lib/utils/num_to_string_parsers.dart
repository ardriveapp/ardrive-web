import 'package:flutter_gen/gen_l10n/app_localizations.dart';

String fileAndFolderCountsToString({
  required int folderCount,
  required int fileCount,
  required AppLocalizations localizations,
}) {
  if (folderCount == 1 && fileCount == 1) {
    // Both singular
    return localizations.folderAndFile(folderCount, fileCount);
  } else if (folderCount == 1 && fileCount != 1) {
    // Folder singular, files plural
    return localizations.folderAndFiles(folderCount, fileCount);
  } else if (folderCount != 1 && fileCount == 1) {
    // Folders plural, file singular
    return localizations.foldersAndFile(folderCount, fileCount);
  } else {
    // Both plural
    return localizations.foldersAndFiles(folderCount, fileCount);
  }
}
