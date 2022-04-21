import 'package:flutter_gen/gen_l10n/app_localizations.dart';

String fileAndFolderCountsToString({
  required int folderCount,
  required int fileCount,
  required AppLocalizations localizations,
}) {
  final folderCountString = localizations.folderCount(folderCount);
  final fileCountString = localizations.fileCount(fileCount);
  return localizations.folderAndFileCountComposite(
      folderCountString, fileCountString);
}
